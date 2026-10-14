#!/usr/bin/env bash
# Symlink dotfiles into $HOME, backing up any existing real files.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

link() {
  local src="$DIR/$1" dest="$HOME/$2"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$dest.bak"
    echo "Backed up $dest -> $dest.bak"
  fi
  ln -sfn "$src" "$dest"
  echo "Linked $dest -> $src"
}

link vimrc .vimrc
