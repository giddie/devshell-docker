#!/usr/bin/env bash

set -euo pipefail

if [[ ! -d ~/.zprezto ]]; then
  ln -s /usr/local/lib/prezto ~/.zprezto
  for dotfile in ~/.zprezto/runcoms/z*; do
    ln -sf $dotfile ~/.$(basename $dotfile)
  done
  mkdir -p ~/.zprezto-extra/misc
  touch ~/.zprezto-extra/misc/init.zsh
fi

if [[ ! -d ~/.asdf ]]; then
  git clone https://github.com/asdf-vm/asdf ~/.asdf
fi
source ~/.asdf/asdf.sh

exec "$@"
