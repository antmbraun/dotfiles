#!/usr/bin/env bash
# On tab.created (which also fires for a new space's first tab), build the shell + status board layout around
# the new tab's first pane.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

tab="$(jq -r 'first(.. | .tab_id? // empty)' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")"
[ -n "$tab" ] || tab="${HERDR_TAB_ID:-}"
[ -n "$tab" ] || { echo "no tab id in event: ${HERDR_PLUGIN_EVENT_JSON:-}" >&2; exit 1; }

# The first pane can take a moment to appear after the tab is created.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  root="$(herdr pane list | jq -r --arg t "$tab" 'first(.result.panes[] | select(.tab_id == $t) | .pane_id) // empty')"
  [ -n "$root" ] && break
  sleep 0.2
done
[ -n "$root" ] || { echo "no pane found in $tab" >&2; exit 1; }

# Skips tabs that already started with a split (e.g. restored or scripted layouts).
exec "$HOME/dotfiles/herdr/apply-layout.sh" "$root"
