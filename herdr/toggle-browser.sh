#!/usr/bin/env bash
# Toggle terminal-browser in the focused herdr tab: close it if one is open, otherwise open a right split.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

current="$(herdr pane current)"
pane="$(jq -r '.result.pane.pane_id' <<<"$current")"
tab="$(jq -r '.result.pane.tab_id' <<<"$current")"

# Key commands run without the pane's env, so terminal-browser can't tell which tab it's in.
export TERM_PROGRAM=herdr HERDR_ENV=1 HERDR_SOCKET_PATH="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"
export HERDR_PANE_ID="$pane" HERDR_TAB_ID="$tab" HERDR_WORKSPACE_ID="${pane%%:*}"

# `terminal-browser ls` rows look like: "<key>  <tab_id>:<pane_id>  ..."
browser_panes="$(terminal-browser ls 2>/dev/null | awk -v tab="$tab" 'index($2, tab ":") == 1 { print substr($2, length(tab) + 2) }')"

if [ -n "$browser_panes" ]; then
  while read -r p; do herdr pane close "$p" >/dev/null; done <<<"$browser_panes"
else
  terminal-browser open --split right >/dev/null
fi
