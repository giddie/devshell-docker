# Features

* Your **project directory** (from the git root) is available in the container.
* Runs as a **non-root user**.
* Runs with the **same UID and GID** as your project root directory. (No more
  files owned by root or other weird UIDs!)
* Your project directory path is the **same inside and outside** the container.
  (Solves a lot of headaches with LSPs!)
* Sets up **ASDF** so you can run the right versions of all your tools.
* Uses a docker volume for the container user's home directory, so that **cached
  artefacts** can be reused later.
* The image is **automatically rebuilt** when running the devshell after modifying
  one of the source files.

# Usage

* Create a `.local` directory in the project I'm working on, and copy this
  template into `.local/devshell`.
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

Then I run commands like this:

```
# ds echo hello world
hello world

# ds bash -c "pwd && id"
/my/project/path
uid=1000(user) gid=100(user) groups=100(user)
```

## Customisation

Be sure to check the volumes that are mounted at the bottom of `devshell`. I
mount my local ZSH config. You may want to make some other host config available
in a similar way.

Also be sure to check `entrypoint-user.sh`, which can be used to set up
project-specific tooling for the non-root user.

Any system packages you need should be added to the Dockerfile.

# Examples

## Running an LSP

Taking `rust-analyzer` as an example, add `.local/bin/rust-analyzer`:

```
#!/usr/bin/env bash
set -euo pipefail
DEVSHELL_DOCKER_OPTS="-i" exec devshell rust-analyzer "$@"
```

So long as you launch your editor from the terminal, where the `.envrc`
has added the `.local/bin` directory to the front of `PATH`, it should run
this wrapper instead of the default `rust-analyzer`. You'll need to ensure
`rust-analyzer` is installed in the container.

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
