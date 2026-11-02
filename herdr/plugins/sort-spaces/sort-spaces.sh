#!/usr/bin/env bash
# Sort herdr spaces (workspaces) by repo, case-insensitive: within a repo, its main space first, then the
# rest by label. Spaces outside any repo go last. A space's repo comes from its herdr worktree group, or
# else from the first git repo its panes are in (the main checkout's name, so worktrees sort with their
# repo). Each space also gets a $repo token for the sidebar.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
SOCK="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"

# The CLI has no `workspace move`, so call the socket API directly.
call() { printf '%s\n' "$1" | nc -U -w 2 "$SOCK"; }

repo_of() {
  local cwd common
  while read -r cwd; do
    common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
    basename "$(dirname "$common")"
    return
  done < <(herdr pane list --workspace "$1" | jq -r '[.result.panes[] | .foreground_cwd // .cwd // empty] | unique | .[]')
}

rows=""
# Fields are split on \x1f, not tabs: read merges runs of tabs, which would drop an empty group.
while IFS=$'\x1f' read -r id label group linked; do
  repo="${group:-$(repo_of "$id")}"
  # The CLI's report-metadata rejects its own flags in 0.9.5, so this goes through the socket too.
  # An empty value clears the token.
  call "$(jq -cn --arg id "$id" --arg repo "$repo" '{id: "repo", method: "workspace.report_metadata", params: {workspace_id: $id, source: "user:sort-spaces", tokens: {repo: $repo}}}')" >/dev/null
  # "~" sorts after letters, so spaces without a repo come last.
  rows+="${repo:-~}"$'\t'"$linked"$'\t'"$label"$'\t'"$id"$'\n'
done < <(herdr workspace list | jq -r '.result.workspaces[] | [.workspace_id, .label, .worktree.repo_name // "", (.worktree.is_linked_worktree // false | tostring)] | join("\u001f")')

i=0
while IFS=$'\t' read -r _ _ _ id; do
  [ -n "$id" ] || continue
  res="$(call "$(jq -cn --arg id "$id" --argjson i "$i" '{id: "sort", method: "workspace.move", params: {workspace_id: $id, insert_index: $i}}')")"
  if jq -e '.error' <<<"$res" >/dev/null; then echo "Failed to move $id: $res" >&2; fi
  i=$((i + 1))
done < <(printf '%s' "$rows" | LC_ALL=C sort -f -t $'\t' -k1,1 -k2,2 -k3,3)
