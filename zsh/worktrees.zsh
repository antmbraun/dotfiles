# Tasks as herdr spaces, and git worktrees with their own DDEV site.
#   task <name> [b2b|play|bkr] [wt]
#                            new herdr space running Claude: in ~/Repos without a repo, in the repo's main
#                            checkout with one, or in a new worktree with `wt`. A name like fix/pricing-cache
#                            is the branch; the part after the slash names the space and folder.
#   space-group <b2b|play|bkr|other>
#                            set which group the current herdr space is listed under
#   wt-new <task> [branch]   new worktree at ../<repo>-<task> on a new branch off the remote's default
#                            branch, with DDEV started and the database copied in. Run inside a repo.
#   wt-setup                 start DDEV in the current worktree and copy the main checkout's database in
#   wt-open <task>           open an existing worktree as a herdr space
#   wt-done <task>           delete that worktree's DDEV project, close its space and remove it

typeset -gA TASK_REPOS=(b2b mktg-web-b2b play mktg-web-playlist bkr mktg-web-booker)
# Each space's group, by label, read by ~/dotfiles/herdr/plugins/sort-spaces/sort-spaces.sh.
SPACE_GROUPS="${XDG_STATE_HOME:-$HOME/.local/state}/herdr/space-groups.tsv"

# Records <label>'s group (a repo folder name, or "other") and re-sorts the spaces.
_space_group_set() {
  mkdir -p "$(dirname "$SPACE_GROUPS")"
  { awk -F'\t' -v l="$1" '$1 != l' "$SPACE_GROUPS" 2>/dev/null; printf '%s\t%s\n' "$1" "$2"; } >"$SPACE_GROUPS.tmp"
  mv "$SPACE_GROUPS.tmp" "$SPACE_GROUPS"
  bash "$HOME/dotfiles/herdr/plugins/sort-spaces/sort-spaces.sh" &>/dev/null &!
}

space-group() {
  local alias="$1"
  if [ "$alias" != other ] && [ -z "${TASK_REPOS[$alias]}" ]; then
    echo "usage: space-group <${(kj:|:)TASK_REPOS}|other>"
    return 1
  fi
  local ws; ws="$(herdr pane current | jq -r '.result.pane.workspace_id')" || return 1
  local label; label="$(herdr workspace get "$ws" | jq -r '.result.workspace.label')"
  _space_group_set "$label" "${TASK_REPOS[$alias]:-other}"
}

# The main checkout, even when run from inside a worktree.
_wt_main() { dirname "$(git ${1:+-C "$1"} rev-parse --path-format=absolute --git-common-dir)"; }

# Opens worktree <dir> of <main> as an ordinary herdr space under its repo's group, and prints herdr's JSON
# response. Not `herdr worktree open`: its groups are indented differently from sort-spaces' headings.
_wt_space() {
  _space_group_set "$3" "$(basename "$1")"
  herdr workspace create --cwd "$2" --label "$3" --focus 2>/dev/null
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
  _wt_space "$main" "$dir" "$task" >/dev/null
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
  local label="${name##*/}" main="" dir="$HOME/Repos" res ws
  [ -n "$alias" ] && main="$HOME/Repos/${TASK_REPOS[$alias]}" dir="$main"
  _space_group_set "$label" "${TASK_REPOS[$alias]:-other}"

  if [ -n "$wt" ]; then
    dir="$main-$label"
    _wt_add "$main" "$label" "$name" || return 1
    res="$(_wt_space "$main" "$dir" "$label")"
  else
    res="$(herdr workspace create --cwd "$dir" --label "$label" --focus)"
  fi
  ws="$(jq -r '.result.workspace.workspace_id // empty' <<<"$res")"
  [ -n "$ws" ] || { echo "couldn't open a herdr space: $res"; return 1; }

  # DDEV setup takes a few minutes, so it runs in its own tab while Claude starts in the first.
  if [ -n "$wt" ] && [ -f "$dir/.ddev/config.yaml" ]; then
    local setup; setup="$(herdr tab create --workspace "$ws" --cwd "$dir" --label setup | jq -r '.result.root_pane.pane_id')"
    herdr pane run "$setup" wt-setup >/dev/null
  fi
  local pane; pane="$(herdr pane list --workspace "$ws" | jq -r '.result.panes[0].pane_id')"
  herdr pane run "$pane" claude >/dev/null
}

wt-open() {
  local task="$1"
  [ -n "$task" ] || { echo "usage: wt-open <task>"; return 1; }
  local main; main="$(_wt_main)" || return 1
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  [ -d "$dir" ] || { echo "no worktree at $dir"; return 1; }
  _wt_space "$main" "$dir" "$task" >/dev/null
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
  # Close the spaces working in the worktree (the shell running this has just left it).
  local space
  for space in $(herdr workspace list 2>/dev/null | jq -r '.result.workspaces[]?.workspace_id'); do
    herdr pane list --workspace "$space" | jq -e --arg d "$dir" 'any(.result.panes[]; (.cwd // "") as $c | $c == $d or ($c | startswith($d + "/")))' >/dev/null &&
      herdr workspace close "$space" >/dev/null
  done
}
