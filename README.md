This provides a temporary, well-defined, and isolated environment for
development. The goal is to provide a way to run your tools with full access to
your project directory and nothing else, in as transparent a way as possible,
and to expose a clean system environment to the wrapped tools to avoid
unpleasant version conflicts and similar complications.

```
$ devshell cargo build
...        <-- Everything compiles inside a temporary container
```

It's also intended to be simple and easy to customise.

# Features

* Your **project directory** (from the git root) is available (read-write) in
  the container.
* Runs as a **non-root user** with **sudo access** (if possible). A password is
  set, to avoid tools switching to root without your knowledge. (The password is:
  `secret`.)
* Runs with the **same UID and GID** as your project root directory. (No
  root-owned files will appear in your project directory!)
* Your project directory path is the **same inside and outside** the container.
  (This solves a lot of headaches with LSPs!)
* Sets up **ASDF** so you can run the right versions of all your
  tools.
* Optional docker volume for the container user's home directory, so that
  **cached artefacts** can be reused later.
* The image is **automatically rebuilt** when running the devshell after
  modifying one of the source files.
* Choose your **base image**: Alpine, ArchLinux, Ubuntu, or easily add your own.

# Usage

You can run the `devshell` script from any directory, and you'll be dropped into
an isolated environment in the same directory, ready to go. Only the directory
you launched the devshell script from will be visible. Inside the devshell,
install whatever you need and go crazy -- it all goes away when you exit the
shell. This may be all you need for a short-term experiment.

You can run stuff non-interactively just fine:

```bash
$ devshell make my-project
$ devshell bash -c "ONE=two\ three env"
```

## Docker Options

By default `docker run` (or `docker exec`) are provided with the `-it` flags
(interaction, TTY). Some non-interactive tools may complain about this. You can
override it like this:

```bash
$ DEVSHELL_DOCKER_OPTS="" devshell scripts/my-script
$ DEVSHELL_DOCKER_OPTS="-i" devshell .local/bin/my-lsp
```

## Variants

The default base image is ArchLinux, but you can choose a different one like
this:

```bash
$ DEVSHELL_VARIANT="alpine" devshell
$ DEVSHELL_VARIANT="ubuntu" devshell
```

You'll find a corresponding Dockerfile for each variant. Creating your own
should be pretty straightforward. There is also a `DEVSHELL_VARIANT` environment
variable available inside the container for any scripts that may want to switch
behaviour based on this.

## Home Volume

You can persist the contents of the home directory `/home/user` in a docker
volume or directory. This is configured by the `DEVSHELL_HOME_VOLUME`
environment variable, like this:

```bash
$ DEVSHELL_HOME_VOLUME="my-project-home" devshell
$ DEVSHELL_HOME_VOLUME=".local/home" devshell
```

The default value is `none`. If you like, you can edit the `devshell` script to
set a different default, in which case setting `DEVSHELL_HOME_VOLUME=none` will
give you the original behaviour (i.e. no docker volume).

## Read-Only Paths

By default, the `.git` and `.local` subdirectories will be mounted read-only
if found, preventing tools inside the devshell from doing anything unexpected
to your git repo or local tools. You can disable this, or set any number of
subdirectories to be read-only, like this:

```bash
$ DEVSHELL_RO_PATHS="" devshell
$ DEVSHELL_RO_PATHS=".git:a/b/My" Secrets:docs devshell
```

## Masked Paths

If you want to hide certain files or directories entirely, you can mask them
like this:

```bash
$ DEVSHELL_MASKED_PATHS=".git:a/b/My Secrets:docs:/proc" devshell
```

For files, this will mount `/dev/null` in its place. For directories, a
root-owned `tmpfs` volume will be mounted on top. Relative paths are relative to
the project root. Absolute paths are supported too.

## Shared Container

By default, running `devshell` will create a separate container for each
invocation. This makes it easy to list and kill them separately from the host
(`docker ps` and `docker kill`). But you can also choose to use a single
container, running additional processes inside the existing container if it
exists. Just choose a name for the container:

```bash
$ DEVSHELL_CONTAINER_NAME="my-container" devshell
```

## SSH

If you want access to your ssh-agent inside the container:

```bash
$ DEVSHELL_SSH=yes devshell
```

## Sudo

> [!NOTE]
> Certain docker server implementations (such as Docker Desktop) will remap UIDs
> in the container so that your UID outside the container is equivalent to root
> inside the container. This can cause some tools to complain about being root.
> The only way to avoid this is to configure your docker environment _not_ to
> map your UID to root.

By default you'll be able to invoke `sudo`, which will require the password
`secret`. If you want to disable all privilege escalation, you can do:

```bash
$ DEVSHELL_SUDO=no devshell
```

If you want to do _some_ actions as root and disable sudo later, you can do this
inside the container when you're ready:

```bash
$ exec setpriv --no-new-privs zsh
```

## Setup for Customisation

This is how I set up the devshell for any project that needs a customised
devshell:

* Create a `.local` directory in the project root, and clone this repository into
  `.local/devshell`.
* Set the `project_name` at the top of the `devshell` script. This determines
  the name of the docker image.
* Also set `default_variant` and `default_home_volume` as needed.
* Create a `.local/bin` directory and add it to `PATH` with a `.envrc`
  file (see [direnv](https://direnv.net/)).
* Add a symlink to the `.local/devshell/devshell` script there.

```
# .envrc
PATH_add .local/bin
```

```
# Structure
.envrc
.local
├── bin
│   ├── devshell -> ../devshell/devshell
│   ├── ds -> devshell
└── devshell
    ├── devshell
    └── ...
```

Then run commands like this:

```bash
$ ds echo hello world
hello world

$ ds bash -c "pwd && id"
/my/project/path
uid=1000(user) gid=100(user) groups=100(user)
```

## Customisation

Generally, you will want to edit the relevant Dockerfile for your default
variant, as well as `entrypoint-user.sh` to set up any tools you need inside the
container.

When creating a new variant Dockerfile, some care may need to be taken in
`entrypoint.sh` that the user and group are set up correctly. You can use the
`DEVSHELL_VARIANT` environment variable if necessary to adjust the behaviour
between different variants.

You probably want to check the volumes that are mounted at the bottom
of `devshell`. I have a local ZSH config that I mount (and activate in
`entrypoint-user.sh`). You may want to tweak that to do something similar for
your preferred setup.

Also be sure to check `entrypoint-user.sh`, which can be used to set up
project-specific tooling for the non-root user.

Any system packages you need should be added to the Dockerfile.

# Examples

## Running an LSP

Taking `rust-analyzer` as an example, add `.local/bin/rust-analyzer`:

```bash
#!/usr/bin/env bash
set -euo pipefail
DEVSHELL_DOCKER_OPTS="-i" exec devshell rust-analyzer "$@"
```

So long as you launch your editor from the terminal, where the `.envrc`
has added the `.local/bin` directory to the front of `PATH`, it should run
this wrapper instead of the default `rust-analyzer`. You'll need to ensure
`rust-analyzer` is installed in the container.

## Nix-Shell

Maybe your project already has a `shell.nix`, and you want to continue handling
your environment there. It's simple enough to get Nix up and running inside the
container:

1. Add a volume to house the Nix store in the `devshell` script, so that it
   gets reused between container instances:
    ```bash
    --volume ${project_name}-nix-store:/nix \
    ```
2. This will be root-owned when docker mounts it, but it's simpler to install
   Nix in single-user mode, so we can fix this in `entrypoint.sh`:
   ```bash
   chown -R $host_uid:$host_gid /nix
   ```
3. Finally, in `entrypoint-user.sh` we install Nix using the official
   single-user install script, and ensure the `bin` directory is in the `PATH`:
   ```bash
   if [[ ! -d ~/.nix-profile ]]; then
     curl -L https://nixos.org/nix/install | sh -s -- --no-daemon
   fi
   PATH=~/.nix-profile/bin:$PATH
   ```
4. Test with: `./devshell nix-shell -p bash`
5. Finally, you can replace the final line of `entrypoint-user.sh` with the
   following, causing the nix shell to wrap everything you run:
    ```bash
    exec nix-shell --command "$*"
    ```

## Docker-in-Docker

If you need to spawn docker containers from inside your dev container, the
simplest approach is to provide access to the host docker socket.

1. Add the socket as a bind-mount in the `devshell` script:
    ```bash
    --volume /var/run/docker.sock:/var/run/docker.sock \
    ```
2. Add `docker` to the list of packages to install in `Dockerfile`.
3. In `entrypoint.sh`, in the final `exec` line, replace `--clear-groups` with:
   `--groups 000`, substituting whatever GID owns the socket file on your host).

## Elixir / Erlang Observer

Running the [observer](https://www.erlang.org/doc/apps/observer/observer_ug)
tool in a container can be tricky, due to an X server not being available.
Fortunately, thanks to BEAM clustering we can simply run the Observer on the
host, and connect to the host from inside the container.

First, we create a script to run a node on the host with a specific name:

```bash
#!/usr/bin/env bash
set -euo pipefail

distribution_port=4370
exec iex \
  --name observer@host.docker.internal \
  --hidden \
  --cookie my-secret-cookie \
  --erl "-kernel inet_dist_listen_min ${distribution_port}" \
  --erl "-kernel inet_dist_listen_max ${distribution_port}"
```

Then we create a script to run a regular node inside the devshell, which
connects to our host:

```bash
#!/usr/bin/env bash
set -euo pipefail

export DEVSHELL_DOCKER_OPTS="-it --add-host host.docker.internal:host-gateway"
host_atom=':"observer@host.docker.internal"'
exec devshell iex \
  --name main@localhost \
  --cookie my-secret-cookie \
  -S mix run \
  -e "Node.connect(${host_atom}); :erpc.call(${host_atom}, :observer, :start, [])"
```

After running the second script, Observer should appear on the host. You can
then click through: `Nodes` -> `main@localhost`.

* The `--add-host ...:host-gateway` switch ensures the container can resolve the
  host IP using the specified domain name. It's important for this to match the
  name used in the first script or EPMD will reject the connection.
* By defining a static distribution port in the first script, we give ourselves
  the option to use ssh port forwarding to forward the connection onward, so we
  don't even have to run Observer on the actual docker host. Forward ports 4369
  (EPMD) and 4370 (distribution port).

# Known Issues

## It tries to rebuild the image each time I launch the devshell!

This happens when docker has figured out that your source files match an
image that it already built previously, such as when you saved a change and
subsequently reverted it. Because the image timestamp is older than the source
files, the devshell script can't tell that it doesn't in fact need to be
rebuilt.

You can fix it by forcing the image to be fully rebuilt like this:

```
# CACHE=no devshell
```
