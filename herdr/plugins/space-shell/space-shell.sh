#!/usr/bin/env bash
# On workspace.created, split a shell to the right of the new space's first pane.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

ws="${HERDR_WORKSPACE_ID:-}"
if [ -z "$ws" ]; then
  ws="$(jq -r 'first(.. | .workspace_id? // empty)' <<<"${HERDR_PLUGIN_EVENT_JSON:-null}")"
fi
[ -n "$ws" ] || { echo "no workspace id in event: ${HERDR_PLUGIN_EVENT_JSON:-}" >&2; exit 1; }

# The first pane can take a moment to appear after the space is created.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  root="$(herdr pane list --workspace "$ws" | jq -r '.result.panes[0].pane_id // empty')"
  [ -n "$root" ] && break
  sleep 0.2
done
[ -n "$root" ] || { echo "no pane found in $ws" >&2; exit 1; }

# Don't add a second shell if the space already started with a split (e.g. restored or scripted layouts).
[ "$(herdr pane list --workspace "$ws" | jq '.result.panes | length')" -eq 1 ] || exit 0

exec "$HOME/dotfiles/herdr/toggle-shell.sh" --open "$root"
