#!/usr/bin/env bash
# Sort herdr spaces (workspaces) by repo, case-insensitive: within a repo, main-checkout spaces first by
# label, then worktree spaces by label. Spaces outside any repo go last. A space's repo comes from its
# herdr worktree group, or else from the first git repo its panes are in (the main checkout's name, so
# worktrees sort with their repo).
# For the sidebar, the first space of each repo gets a $heading token with the repo's name, and spaces in a
# worktree get a $worktree token.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
SOCK="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"
US=$'\x1f'

# The CLI has no `workspace move`, and its report-metadata rejects its own flags in 0.9.5, so call the
# socket API directly.
call() { printf '%s\n' "$1" | nc -U -w 2 "$SOCK"; }

# Prints "<repo><US><true if a linked worktree>" for the first git repo the space's panes are in.
repo_of() {
  local cwd common gitdir
  while read -r cwd; do
    common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
    gitdir="$(git -C "$cwd" rev-parse --path-format=absolute --git-dir)"
    printf '%s%s%s' "$(basename "$(dirname "$common")")" "$US" "$([ "$gitdir" != "$common" ] && echo true || echo false)"
    return
  done < <(herdr pane list --workspace "$1" | jq -r '[.result.panes[] | .foreground_cwd // .cwd // empty] | unique | .[]')
}

rows=""
# Fields are split on \x1f, not tabs: read merges runs of tabs, which would drop an empty group.
while IFS="$US" read -r id label group linked; do
  if [ -z "$group" ]; then IFS="$US" read -r group linked <<<"$(repo_of "$id")" || true; fi
  # "~" sorts after letters, so spaces without a repo come last.
  rows+="${group:-~}"$'\t'"${linked:-false}"$'\t'"$label"$'\t'"$id"$'\n'
done < <(herdr workspace list | jq -r '.result.workspaces[] | [.workspace_id, .label, .worktree.repo_name // "", (.worktree.is_linked_worktree // false | tostring)] | join("\u001f")')

i=0
prev=""
while IFS=$'\t' read -r repo linked _ id; do
  [ -n "$id" ] || continue
  res="$(call "$(jq -cn --arg id "$id" --argjson i "$i" '{id: "sort", method: "workspace.move", params: {workspace_id: $id, insert_index: $i}}')")"
  if jq -e '.error' <<<"$res" >/dev/null; then echo "Failed to move $id: $res" >&2; fi

  heading=""
  if [ "$repo" != "$prev" ]; then heading="$([ "$repo" = "~" ] && echo "other" || echo "$repo")"; fi
  worktree="$([ "$linked" = true ] && echo "⎇ worktree" || true)"
  # An empty value clears the token. repo is the token this plugin used to set.
  call "$(jq -cn --arg id "$id" --arg h "$heading" --arg w "$worktree" '{id: "tokens", method: "workspace.report_metadata", params: {workspace_id: $id, source: "user:sort-spaces", tokens: {heading: $h, worktree: $w, repo: ""}}}')" >/dev/null

  prev="$repo"
  i=$((i + 1))
done < <(printf '%s' "$rows" | LC_ALL=C sort -f -t $'\t' -k1,1 -k2,2 -k3,3)
