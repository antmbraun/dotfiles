#!/usr/bin/env bash
# Build the space layout around a pane: it stays on the left half, a shell goes top-right, the status board bottom-right.
# Usage: apply-layout.sh [pane_id]   (defaults to the focused pane; does nothing if its tab is already split)
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

if [ -n "${1:-}" ]; then
  info="$(herdr pane get "$1")"
else
  info="$(herdr pane current)"
fi
root="$(jq -r '.result.pane.pane_id' <<<"$info")"
tab="$(jq -r '.result.pane.tab_id' <<<"$info")"
cwd="$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd' <<<"$info")"

[ "$(herdr pane list | jq --arg tab "$tab" '[.result.panes[] | select(.tab_id == $tab)] | length')" -eq 1 ] || exit 0

"$HOME/dotfiles/herdr/toggle-shell.sh" --open "$root"
shell_pane="$(cat "${XDG_STATE_HOME:-$HOME/.local/state}/herdr-toggle-shell/${tab//:/_}")"
status_pane="$(herdr pane split --pane "$shell_pane" --direction down --cwd "$cwd" --no-focus | jq -r '.result.pane.pane_id')"
herdr pane run "$status_pane" "exec $HOME/dotfiles/herdr/space-status.sh $root" >/dev/null
