#!/usr/bin/env bash
# Symlink dotfiles into $HOME, backing up any existing real files.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

link() {
  local src="$DIR/$1" dest="$HOME/$2"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    local backup="$dest.dotfiles-backup.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup"
    echo "Backed up $dest -> $backup"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  echo "Linked $dest -> $src"
}

link vimrc .vimrc
link herdr/config.toml .config/herdr/config.toml

if command -v herdr >/dev/null 2>&1; then
  herdr plugin link "$DIR/herdr/plugins/sort-spaces" >/dev/null && echo "Linked herdr plugin sort-spaces"
fi
