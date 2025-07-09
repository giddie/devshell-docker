#!/usr/bin/env bash

set -euo pipefail

if [[ ! -a ~/.zshrc && ! -d ~/.zprezto ]]; then
  if [[ -d /usr/local/lib/prezto/runcoms ]]; then
    ln -s /usr/local/lib/prezto ~/.zprezto
  else
    echo -n "Would you like a nice shell prompt? [Y/n]: "
    read -r yn
    case "$yn" in
      "" | [Yy]*) git clone --recursive https://github.com/giddie/prezto.git ~/.zprezto; break ;;
      *) touch ~/.zshrc ;;
    esac
  fi

  if [[ -d ~/.zprezto ]]; then
    for dotfile in ~/.zprezto/runcoms/z*; do
      ln -sf $dotfile ~/.$(basename $dotfile)
    done

    mkdir -p ~/.zprezto-extra/misc
    touch ~/.zprezto-extra/misc/init.zsh
  fi
fi

# if [[ ! -d ~/.asdf ]]; then
#   asdf plugin add ...
#   asdf install
# fi
export PATH=~/.asdf/shims:$PATH

exec "$@"
