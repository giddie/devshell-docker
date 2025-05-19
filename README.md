This provides a transient, well-defined, and isolated environment for
development. The goal is to provide a way to run your tools with full access to
your project directory and nothing else, in as transparent a way as possible,
and to expose a clean system environment to the wrapped tools to avoid
unpleasant version conflicts and similar complications.

```
# devshell cargo build
...        <-- Everything compiles inside a temporary container
```

# Features

* Your **project directory** (from the git root) is available (read-write) in
  the container.
* Runs as a **non-root user** with **sudo access**. A password is set, to avoid
  tools switching to root without your knowledge. (The password is: `secret`.)
* Runs with the **same UID and GID** as your project root directory. (No
  root-owned files will appear in your project directory!)
* Your project directory path is the **same inside and outside** the container.
  (This solves a lot of headaches with LSPs!)
* Sets up **ASDF** so you can run the right versions of all your tools.
* Uses a docker volume for the container user's home directory, so that **cached
  artefacts** can be reused later.
* The image is **automatically rebuilt** when running the devshell after modifying
  one of the source files.

# Usage

You can run it exactly as it is, but this is how I set it up within a given
project:

* Create a `.local` directory in the project root, and copy this template into
  `.local/devshell`.
* Set the `project_name` in the `devshell` script. This determines the name of
  the docker image and volume.
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

The Dockerfile on the default branch is Archlinux-based. Check out the `ubuntu`
branch for an Ubuntu-based devshell. Generally, apart from the Dockerfile not
much needs to change when you use a different base image. Some care may need to
be taken in `entrypoint.sh` that the user and group are set up correctly.

Be sure to check the volumes that are mounted at the bottom of `devshell`. I
mount my local ZSH config. You may want to make some other host config available
in a similar way.

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

## Running several things in the same container

The script will spawn a fresh container on each invocation by default. If you
want to run several things in the same container, this is relatively
straightforward with a wrapper script:

```bash
#!/usr/bin/env bash
set -euo pipefail
container_name="my-project-main"
container_id=$(docker container ls -q --filter=name=$container_name)
if [[ $container_id ]]; then
  docker exec -it $container_id /usr/local/bin/entrypoint.sh /bin/zsh
else
  DEVSHELL_DOCKER_OPTS="-it --name $container_name" devshell
fi
```

## Elixir / Erlang Observer

Running the [observer](https://www.erlang.org/doc/apps/observer/observer_ug)
tool in a container can be tricky, due to an X server not being available.
Fortunately, thanks to BEAM clustering we can simply run the Observer on the
host, and then connect to the node inside the container.

First, we create a script that runs our node inside the container. The only
tricky bit here is that we need to know the IP of the container before we start
our node. We give the container a name so we can look up its IP later:

```bash
#!/usr/bin/env bash
set -euo pipefail
DEVSHELL_DOCKER_OPTS="-it --name my-main-node" \
  devshell bash -c "\
    ip=\$(ip -4 addr show eth0 | grep inet | head -n1 | xargs echo | cut -d' ' -f2 | cut -d/ -f1);
    iex --name main@\$ip --cookie my-secret-cookie -S mix
  "
```

And then, we can create a script that spawns a node on the host, connects to our
main node, and launches the observer:

```bash
#!/usr/bin/env bash
set -euo pipefail

node_ip=$(
  docker container inspect my-main-node -f '{{json .NetworkSettings}}' \
    | jq -r '.Networks[].IPAddress' \
    | head -n1
)

iex \
  --name host@localhost \
  --hidden \
  --cookie my-secret-cookie \
  -e "Node.connect(:'main@${node_ip}'); :observer.start"
```

And then click through: `Nodes` -> `main@...`.

Note that clustering _between_ containers is a little simpler: so long as they are
connected to the same docker network, you can rely on DNS to resolve container
names instead of figuring out IPs.

# Known Issues

## It tries to rebuild the image each time I launch the devshell!

This happens when docker has figured out that your source files match an image
that it already built previously, such as when you saved a change and
subsequently reverted it. Because the image timestamp is older than the source
files, the devshell script can't tell that it doesn't in fact need to be
rebuilt.

You can fix it by forcing a rebuild without the docker cache:

```
# docker build --no-cache .
```
