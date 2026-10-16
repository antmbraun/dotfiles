#!/usr/bin/env bash
# Toggle lazygit in the focused herdr tab: close it if one is open, otherwise open a right split in the focused pane's cwd.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

current="$(herdr pane current)"
pane="$(jq -r '.result.pane.pane_id' <<<"$current")"
tab="$(jq -r '.result.pane.tab_id' <<<"$current")"
cwd="$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd' <<<"$current")"

lazygit_panes=()
for p in $(herdr pane list | jq -r --arg tab "$tab" '.result.panes[] | select(.tab_id == $tab) | .pane_id'); do
  if herdr pane process-info --pane "$p" | jq -e '.result.process_info.foreground_processes[] | select(.argv0 == "lazygit")' >/dev/null; then
    lazygit_panes+=("$p")
  fi
done

if [ "${#lazygit_panes[@]}" -gt 0 ]; then
  for p in "${lazygit_panes[@]}"; do herdr pane close "$p" >/dev/null; done
elif git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  new="$(herdr pane split --pane "$pane" --direction right --cwd "$cwd" --focus | jq -r '.result.pane.pane_id')"
  # exec so the pane closes when lazygit quits
  herdr pane run "$new" "exec lazygit" >/dev/null
fi
