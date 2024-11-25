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
host, and then connect to the node inside the container:

First, we create a script that runs our node inside the container with some
proxying magic in place:

```bash
#!/usr/bin/env bash
set -euo pipefail
DEVSHELL_DOCKER_OPTS=$(echo \
  -it \
  -p 127.0.0.1:9000:9000 \
  -p 127.0.0.1:9001:9001 \
  ) \
  devshell bash -c "\
    socat TCP-LISTEN:9000,fork TCP:localhost:4369 & \
    iex --sname main@localhost \
        --cookie mysecretcookie \
        --erl '-kernel inet_dist_listen_min 9001 inet_dist_listen_max 9001' \
        -S mix
  "
```

This ensures that the VM inside the container is running
[epmd](https://www.erlang.org/docs/19/man/epmd.html) and the node distribution
port on ports of our choosing (which also don't conflict with any other local
nodes that happen to be running). And then, when we want to observe the node:

```bash
#!/usr/bin/env bash
set -euo pipefail
export ERL_EPMD_PORT=9000
epmd -names > /dev/null || (2>&1 echo The remote node is not running. && exit 1)
/usr/bin/iex \
  --sname host@localhost \
  --hidden \
  --cookie mysecretcookie \
  -e "Node.connect(:'main@localhost'); :observer.start"
```

And then click through: `Nodes` -> `main@localhost`.

The way this works is that the node on the host will connect to the `epmd`
instance that is already running inside the container, and will register its
name there. This means that it believes it is a second node running inside the
same container, and doesn't need to resolve a hostname to connect to the node
remotely (which would otherwise be awkward to configure on the host). After
looking up the target node's distribution port in `epmd` (via port 9000), the
host node is then able to connect to the container node via port 9001.

The `socat` trick is used because `epmd` permits only connections from localhost
to register new node names. So we need to proxy the connection so that it looks
like the connection is coming from inside the container.

Note that clustering _between_ containers is much simpler: so long as they are
connected to the same docker network, they can resolve each-other's hostnames
and no special tricks are needed. This trick is needed only because docker hosts
do not resolve container hostnames.

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
