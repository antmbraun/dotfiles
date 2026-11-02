# Tasks as herdr tabs, grouped in one space per repo, and git worktrees with their own DDEV site.
#   task <name> [b2b|play|bkr] [wt]
#                            new tab running Claude in the repo's space (b2b, play, bkr, or "other" without a
#                            repo), creating the space if needed. It works in ~/Repos without a repo, in the
#                            repo's main checkout with one, or in a new worktree with `wt`. A name like
#                            fix/pricing-cache is the branch; the part after the slash names the tab and folder.
#   wt-new <task> [branch]   new worktree at ../<repo>-<task> on a new branch off the remote's default
#                            branch, with DDEV started and the database copied in. Run inside a repo.
#   wt-setup                 start DDEV in the current worktree and copy the main checkout's database in
#   wt-open <task>           open an existing worktree as a tab in its repo's space
#   wt-done <task>           delete that worktree's DDEV project, close its tab and remove it

typeset -gA TASK_REPOS=(b2b mktg-web-b2b play mktg-web-playlist bkr mktg-web-booker)

# The main checkout, even when run from inside a worktree.
_wt_main() { dirname "$(git ${1:+-C "$1"} rev-parse --path-format=absolute --git-common-dir)"; }

# The space's short name for a main checkout: its TASK_REPOS key, or "other".
_task_space_name() {
  local k
  for k in ${(k)TASK_REPOS}; do [ "$HOME/Repos/${TASK_REPOS[$k]}" = "$1" ] && { echo "$k"; return; }; done
  echo other
}

# Opens a tab named <label> in <dir>, in the space named <space> (created in <space_cwd> if needed), and
# focuses it. The space-shell plugin lays out the tab; this waits for that and prints
# "<main pane> <shell pane>".
_task_tab() {
  local space="$1" space_cwd="$2" dir="$3" label="$4" ws res tab root
  ws="$(herdr workspace list | jq -r --arg s "$space" 'first(.result.workspaces[] | select(.label == $s) | .workspace_id) // empty')"
  if [ -z "$ws" ]; then
    # A new space comes with a first tab, which becomes this task's.
    res="$(herdr workspace create --cwd "$dir" --label "$space")"
    ws="$(jq -r '.result.workspace.workspace_id // empty' <<<"$res")"
    tab="$(jq -r '.result.tab.tab_id // empty' <<<"$res")"
    [ -n "$tab" ] && herdr tab rename "$tab" "$label" >/dev/null
  else
    res="$(herdr tab create --workspace "$ws" --cwd "$dir" --label "$label")"
    tab="$(jq -r '.result.tab.tab_id // empty' <<<"$res")"
  fi
  root="$(jq -r '.result.root_pane.pane_id // empty' <<<"$res")"
  [ -n "$root" ] || { echo "couldn't open a herdr tab: $res" >&2; return 1; }
  herdr workspace focus "$ws" >/dev/null
  herdr tab focus "$tab" >/dev/null

  local state="${XDG_STATE_HOME:-$HOME/.local/state}/herdr-toggle-shell/${tab//:/_}" i
  for i in {1..50}; do [ -s "$state" ] && break; sleep 0.2; done
  echo "$root $(cat "$state" 2>/dev/null)"
}

# Adds a worktree for <main> at ../<repo>-<task> on a new <branch> off the remote's default branch.
_wt_add() {
  local main="$1" task="$2" branch="$3"
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  local remote; remote="$(git -C "$main" remote | head -1)"
  local base; base="$(git -C "$main" symbolic-ref -q --short "refs/remotes/$remote/HEAD")" || base="$remote/master"
  git -C "$main" fetch -q "$remote" || return 1
  git -C "$main" worktree add -q --no-track "$dir" -b "$branch" "$base" || return 1
}

wt-new() {
  local task="$1" branch="${2:-$1}"
  [ -n "$task" ] || { echo "usage: wt-new <task> [branch]"; return 1; }
  local main; main="$(_wt_main)" || return 1
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  _wt_add "$main" "$task" "$branch" || return 1
  _task_tab "$(_task_space_name "$main")" "$main" "$dir" "$task" >/dev/null
  cd "$dir" && wt-setup
}

wt-setup() {
  [ -f .ddev/config.yaml ] || return 0
  local main; main="$(_wt_main)" || return 1
  # A fixed name in config.yaml would collide with the main checkout's site; name it after the folder.
  if grep -q '^name:' .ddev/config.yaml; then
    echo "name: $(basename "$PWD")" >.ddev/config.local.yaml
  fi
  ddev start && ddev composer install || return 1
  git checkout -q -- . # composer's theme build can rewrite lock files

  # Copy the database from the main checkout's site, starting it if needed; fall back to Pantheon.
  local dump; dump="$(mktemp -d)/db.sql.gz"
  if (cd "$main" && ddev start >/dev/null && ddev export-db --file="$dump"); then
    ddev import-db --file="$dump"
  else
    ddev pull pantheon -y
  fi
  rm -rf "$(dirname "$dump")"
  ddev describe -j | jq -r .raw.primary_url
}

task() {
  local name="$1" alias="$2" wt="$3"
  if [ -z "$name" ] || { [ -n "$wt" ] && [ "$wt" != wt ]; } || { [ -n "$alias" ] && [ -z "${TASK_REPOS[$alias]}" ]; }; then
    echo "usage: task <name> [${(kj:|:)TASK_REPOS}] [wt]"
    return 1
  fi
  local label="${name##*/}" main="$HOME/Repos" dir="$HOME/Repos" panes
  [ -n "$alias" ] && main="$HOME/Repos/${TASK_REPOS[$alias]}" dir="$main"
  if [ -n "$wt" ]; then
    dir="$main-$label"
    _wt_add "$main" "$label" "$name" || return 1
  fi

  panes=($(_task_tab "${alias:-other}" "$main" "$dir" "$label")) || return 1
  herdr pane run "${panes[1]}" claude >/dev/null
  # DDEV setup takes a few minutes, so it runs in the tab's shell while Claude starts.
  if [ -n "$wt" ] && [ -f "$dir/.ddev/config.yaml" ] && [ -n "${panes[2]}" ]; then
    herdr pane run "${panes[2]}" wt-setup >/dev/null
  fi
}

wt-open() {
  local task="$1"
  [ -n "$task" ] || { echo "usage: wt-open <task>"; return 1; }
  local main; main="$(_wt_main)" || return 1
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  [ -d "$dir" ] || { echo "no worktree at $dir"; return 1; }
  _task_tab "$(_task_space_name "$main")" "$main" "$dir" "$task" >/dev/null
}

wt-done() {
  local task="$1"
  [ -n "$task" ] || { echo "usage: wt-done <task>"; return 1; }
  local main; main="$(_wt_main)" || return 1
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  [ -d "$dir" ] || { echo "no worktree at $dir"; return 1; }

  local branch; branch="$(git -C "$dir" branch --show-current)"
  [ -f "$dir/.ddev/config.yaml" ] && (cd "$dir" && ddev delete -Oy)
  case "$PWD/" in "$dir"/*) cd "$main" ;; esac
  git -C "$main" worktree remove "$dir" || return 1
  # -d keeps branches that haven't been merged.
  [ -n "$branch" ] && git -C "$main" branch -d "$branch" 2>/dev/null
  echo "Removed $dir"
  # Close the tabs working in the worktree (the shell running this has just left it).
  local tab
  for tab in $(herdr pane list | jq -r --arg d "$dir" '[.result.panes[] | select((.cwd // "") as $c | $c == $d or ($c | startswith($d + "/"))) | .tab_id] | unique | .[]'); do
    herdr tab close "$tab" >/dev/null
  done
}
