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
link ghostty/config .config/ghostty/config

# Shared Claude instructions for both accounts.
for claude_dir in .claude .claude-personal; do
  link claude/CLAUDE.md "$claude_dir/CLAUDE.md"
  link claude/rules "$claude_dir/rules"
done

# Source the zsh snippets from .zshrc (zshrc itself stays machine-local).
# colors.zsh goes last: syntax highlighting must load after everything else.
for snippet in claude-accounts.zsh colors.zsh; do
  source_line="source \"$DIR/zsh/$snippet\""
  if ! grep -qF "$source_line" "$HOME/.zshrc" 2>/dev/null; then
    printf '\n%s\n' "$source_line" >>"$HOME/.zshrc"
    echo "Added $snippet to ~/.zshrc"
  fi
done

if command -v brew >/dev/null 2>&1 && ! brew list zsh-syntax-highlighting >/dev/null 2>&1; then
  brew install zsh-syntax-highlighting
fi

# Two Claude accounts: work in ~/.claude, personal in ~/.claude-personal.
claude_dirs=("$HOME/.claude" "$HOME/.claude-personal")
mkdir -p "${claude_dirs[@]}"

# Point Claude Code's status line at the script, without touching the rest of settings.json.
for claude_dir in "${claude_dirs[@]}"; do
  settings="$claude_dir/settings.json"
  if command -v jq >/dev/null 2>&1 && ! jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
    [ -f "$settings" ] || echo '{}' >"$settings"
    tmp="$(mktemp)"
    jq '.statusLine = {type: "command", command: "bash ~/.claude/statusline-command.sh"}' "$settings" >"$tmp" && mv "$tmp" "$settings"
    echo "Set statusLine in $settings"
  fi

  # Show each prompt under its space in herdr's sidebar.
  hook="bash $DIR/claude/hooks/herdr-last-prompt.sh"
  if command -v jq >/dev/null 2>&1 && ! jq -e --arg h "$hook" '[.hooks.UserPromptSubmit[]?.hooks[]?.command] | index($h)' "$settings" >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg h "$hook" '.hooks.UserPromptSubmit += [{hooks: [{type: "command", command: $h}]}]' "$settings" >"$tmp" && mv "$tmp" "$settings"
    echo "Added UserPromptSubmit hook in $settings"
  fi
done

if command -v herdr >/dev/null 2>&1; then
  for plugin in sort-spaces space-shell; do
    herdr plugin link "$DIR/herdr/plugins/$plugin" >/dev/null && echo "Linked herdr plugin $plugin"
  done
  for claude_dir in "${claude_dirs[@]}"; do
    CLAUDE_CONFIG_DIR="$claude_dir" herdr integration install claude >/dev/null && echo "Installed herdr claude integration in $claude_dir"
  done
fi
