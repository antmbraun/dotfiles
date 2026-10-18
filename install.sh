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
link claude/statusline-command.sh .claude/statusline-command.sh

# Point Claude Code's status line at the script, without touching the rest of settings.json.
settings="$HOME/.claude/settings.json"
if command -v jq >/dev/null 2>&1 && ! jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
  [ -f "$settings" ] || echo '{}' >"$settings"
  tmp="$(mktemp)"
  jq '.statusLine = {type: "command", command: "bash ~/.claude/statusline-command.sh"}' "$settings" >"$tmp" && mv "$tmp" "$settings"
  echo "Set statusLine in $settings"
fi

if command -v herdr >/dev/null 2>&1; then
  for plugin in sort-spaces space-shell; do
    herdr plugin link "$DIR/herdr/plugins/$plugin" >/dev/null && echo "Linked herdr plugin $plugin"
  done
fi
