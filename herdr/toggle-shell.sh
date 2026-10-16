#!/usr/bin/env bash
# Toggle a shell split in the focused herdr tab: open one to the right in the focused pane's cwd,
# or close the one this script opened if it's sitting at an idle prompt.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-toggle-shell"
mkdir -p "$STATE_DIR"

current="$(herdr pane current)"
pane="$(jq -r '.result.pane.pane_id' <<<"$current")"
tab="$(jq -r '.result.pane.tab_id' <<<"$current")"
cwd="$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd' <<<"$current")"
state="$STATE_DIR/${tab//:/_}"

if [ -f "$state" ]; then
  shell_pane="$(cat "$state")"
  if info="$(herdr pane process-info --pane "$shell_pane" 2>/dev/null)" && jq -e '.result' <<<"$info" >/dev/null; then
    # Only close it at an idle shell prompt, so a running command is never killed.
    if jq -e '.result.process_info.foreground_processes | all(.argv0 | test("^-?(zsh|bash|sh|fish)$"))' <<<"$info" >/dev/null; then
      herdr pane close "$shell_pane" >/dev/null
      rm -f "$state"
    fi
    exit 0
  fi
  rm -f "$state" # pane is gone; open a fresh one
fi

herdr pane split --pane "$pane" --direction right --cwd "$cwd" --focus | jq -r '.result.pane.pane_id' >"$state"
