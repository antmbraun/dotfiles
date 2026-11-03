#!/usr/bin/env bash
# List each herdr space's tasks (its tabs) under it in the sidebar, through workspace tokens:
#   $summary   "3 tasks · 1 needs you · 2 sites up"
#   $tN, $bN   task N's state icon and name, and its branch, worktree mark and PR (N = 1..MAX)
# Agent state and branch come from `herdr agent list`; the branch token is reported by
# ~/dotfiles/claude/statusline-command.sh. Sites are running DDEV projects in the space's repo checkouts.
set -euo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
MAX=14 # rows left in herdr's 16-row space layout after the space's own line

# Events come in bursts (an agent flips state, a tab opens); one refresh at a time, and one more if any
# arrived while it ran.
LOCK="${TMPDIR:-/tmp}/herdr-space-tasks.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  touch "$LOCK/again"
  exit 0
fi
trap 'rm -rf "$LOCK"' EXIT

# TASK_REPOS from ~/dotfiles/zsh/worktrees.zsh as "<space> <repo folder> ...".
TASK_REPOS="$(sed -n 's/^typeset -gA TASK_REPOS=(\(.*\))$/\1/p' "$HOME/dotfiles/zsh/worktrees.zsh")"
repo_of() { awk -v s="$1" '{for (i = 1; i < NF; i += 2) if ($i == s) print $(i + 1)}' <<<"$TASK_REPOS"; }

refresh() {
  local agents sites ws label repo tabs tab tlabel i tokens status branch icon line detail count needs up
  agents="$(herdr agent list)"
  sites="$(ddev list -j 2>/dev/null | jq -c '[.raw[]? | select(.status == "running") | .approot]' || echo '[]')"

  while IFS=$'\t' read -r ws label; do
    tabs="$(herdr tab list --workspace "$ws")"
    tokens='{}' i=0 needs=0
    while IFS=$'\t' read -r tab tlabel; do
      i=$((i + 1))
      [ "$i" -le "$MAX" ] || continue
      line="$(jq -r --arg t "$tab" 'first(.result.agents[] | select(.tab_id == $t)) | [.agent_status, (.tokens.branch // "")] | @tsv' <<<"$agents")"
      status="${line%%$'\t'*}" branch="${line#*$'\t'}"
      [ -n "$line" ] || status="" branch=""
      case "$status" in
        working) icon="◐" ;;
        blocked) icon="!" needs=$((needs + 1)) ;;
        done) icon="✓" ;;
        idle) icon="●" ;;
        *) icon="○" ;;
      esac
      # "mktg-web-b2b ⎇ fix/x (worktree) #3201" -> "fix/x ⎇ #3201": the space already names the repo.
      detail="${branch#* ⎇ }"
      detail="${detail/ (worktree)/ ⎇}"
      tokens="$(jq -c --arg n "$i" --arg t "$icon $tlabel" --arg b "$detail" '. + {("t" + $n): $t, ("b" + $n): $b}' <<<"$tokens")"
    done < <(jq -r '.result.tabs[] | [.tab_id, .label] | @tsv' <<<"$tabs")
    count="$i"

    # Clear rows left over from tasks that have closed. An empty value clears a token.
    while [ "$i" -lt "$MAX" ]; do
      i=$((i + 1))
      tokens="$(jq -c --arg n "$i" '. + {("t" + $n): "", ("b" + $n): ""}' <<<"$tokens")"
    done

    line="$count task$([ "$count" = 1 ] || echo s)"
    [ "$needs" -gt 0 ] && line+=" · $needs need$([ "$needs" = 1 ] && echo s) you"
    repo="$(repo_of "$label")"
    if [ -n "$repo" ]; then
      # The main checkout and its worktrees (../<repo>-<task>).
      up="$(jq -r --arg r "$HOME/Repos/$repo" '[.[] | select(. == $r or startswith($r + "-"))] | length' <<<"$sites")"
      line+=" · $up site$([ "$up" = 1 ] || echo s) up"
    fi
    tokens="$(jq -c --arg s "$line" '. + {summary: $s}' <<<"$tokens")"

    # A report may carry at most 16 tokens, so send them in batches.
    jq -c 'to_entries | _nwise(15) | from_entries' <<<"$tokens" | while read -r batch; do
      printf '%s\n' "$(jq -cn --arg w "$ws" --argjson t "$batch" '{id: "tasks", method: "workspace.report_metadata", params: {workspace_id: $w, source: "user:space-tasks", tokens: $t}}')" |
        nc -U -w 2 "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" >/dev/null
    done
  done < <(herdr workspace list | jq -r '.result.workspaces[] | [.workspace_id, .label] | @tsv')
}

refresh
while [ -e "$LOCK/again" ]; do
  rm -f "$LOCK/again"
  refresh
done
