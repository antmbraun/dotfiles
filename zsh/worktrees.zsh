# Git worktrees with their own DDEV site. Run from anywhere inside a repo's checkout.
#   wt-new <task> [branch]   new worktree at ../<repo>-<task> on a new branch off the remote's
#                            default branch, with DDEV started and the database copied in
#   wt-open <task>           open an existing worktree as a herdr space, grouped under its repo
#   wt-done <task>           delete that worktree's DDEV project, close its space and remove it

# The main checkout, even when run from inside a worktree.
_wt_main() { dirname "$(git rev-parse --path-format=absolute --git-common-dir)"; }

# herdr's worktree open groups the space under the repo's main space, opening that one too if needed.
_wt_space() { herdr worktree open --cwd "$1" --path "$2" --label "$3" --focus >/dev/null 2>&1 || true; }

wt-new() {
  local task="$1" branch="${2:-$1}"
  [ -n "$task" ] || { echo "usage: wt-new <task> [branch]"; return 1; }
  local main; main="$(_wt_main)" || return 1
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  local remote; remote="$(git -C "$main" remote | head -1)"
  local base; base="$(git -C "$main" symbolic-ref -q --short "refs/remotes/$remote/HEAD")" || base="$remote/master"

  git -C "$main" fetch -q "$remote" || return 1
  git -C "$main" worktree add --no-track "$dir" -b "$branch" "$base" || return 1
  _wt_space "$main" "$dir" "$task"
  cd "$dir" || return 1

  if [ -f .ddev/config.yaml ]; then
    # A fixed name in config.yaml would collide with the main checkout's site; name it after the folder.
    if grep -q '^name:' .ddev/config.yaml; then
      echo "name: $(basename "$dir")" >.ddev/config.local.yaml
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
  fi
}

wt-open() {
  local task="$1"
  [ -n "$task" ] || { echo "usage: wt-open <task>"; return 1; }
  local main; main="$(_wt_main)" || return 1
  local dir="$(dirname "$main")/$(basename "$main")-$task"
  [ -d "$dir" ] || { echo "no worktree at $dir"; return 1; }
  _wt_space "$main" "$dir" "$task"
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
  local space; space="$(herdr workspace list 2>/dev/null | jq -r --arg d "$dir" '.result.workspaces[]? | select(.worktree.checkout_path == $d) | .workspace_id')"
  [ -n "$space" ] && herdr workspace close "$space" >/dev/null
  echo "Removed $dir"
}
