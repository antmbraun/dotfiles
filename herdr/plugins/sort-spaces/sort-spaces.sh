#!/usr/bin/env bash
# Sort herdr spaces (workspaces) alphabetically by label, case-insensitive.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
SOCK="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"

# The CLI has no `workspace move`, so call the socket API directly.
call() { printf '%s\n' "$1" | nc -U -w 2 "$SOCK"; }

ids="$(herdr workspace list | jq -r '.result.workspaces | sort_by(.label | ascii_downcase) | .[].workspace_id')"

i=0
while read -r id; do
  res="$(call "$(jq -cn --arg id "$id" --argjson i "$i" '{id: "sort", method: "workspace.move", params: {workspace_id: $id, insert_index: $i}}')")"
  if jq -e '.error' <<<"$res" >/dev/null; then echo "Failed to move $id: $res" >&2; fi
  i=$((i + 1))
done <<<"$ids"
