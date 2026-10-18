#!/bin/bash
# Claude Code statusline: model + context bar + repo/branch/sync/PR + ddev +
# rate-limit usage + session cost.
# Reads the statusline JSON payload on stdin.

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
mkdir -p "$CACHE_DIR"

# cached <key> <ttl-seconds> <cmd...>: print the last cached result immediately
# and, once it is older than ttl, refresh it in the background. gh and docker
# each take 0.4-1s, which would stall every statusline render if run inline.
cached() {
  local key=$1 ttl=$2; shift 2
  local f="$CACHE_DIR/$(printf '%s' "$key" | shasum | cut -c1-16)"
  local age=$ttl
  [ -f "$f" ] && age=$(( $(date +%s) - $(stat -f %m "$f") ))
  if [ "$age" -ge "$ttl" ]; then
    # Touch first so renders during the refresh don't spawn duplicates.
    touch "$f"
    # Detach fully: a child holding stdout open would block the statusline.
    ( "$@" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" || rm -f "$f.tmp" ) </dev/null >/dev/null 2>&1 &
  fi
  cat "$f" 2>/dev/null
}

# --- palette (respects NO_COLOR) ---------------------------------------------
if [ -n "$NO_COLOR" ]; then
  R= B= DIM= SEP_C= NAME= GREEN= YELLOW= RED= BRANCH_C=
else
  R=$'\033[0m'      ; B=$'\033[1m'
  DIM=$'\033[2m'
  NAME=$'\033[38;5;110m'                  # soft blue
  BRANCH_C=$'\033[38;5;140m'              # muted purple
  GREEN=$'\033[38;5;114m'
  YELLOW=$'\033[38;5;179m'
  RED=$'\033[38;5;203m'
  SEP_C=$'\033[38;5;240m'
fi

SEP="${SEP_C}  ${DIM}·${R}${SEP_C}  ${R}"

# Pick a color for a 0-100 percentage: calm until it matters.
heat() {
  if   [ "$1" -ge 85 ]; then printf '%s' "$RED"
  elif [ "$1" -ge 60 ]; then printf '%s' "$YELLOW"
  else                       printf '%s' "$GREEN"
  fi
}

parts=()

# --- model -------------------------------------------------------------------
parts+=("${NAME}${B}${model}${R}")

# --- context window: eighth-block bar for sub-cell precision -----------------
if [ -n "$ctx" ]; then
  pct=$(printf '%.0f' "$ctx")
  [ "$pct" -gt 100 ] && pct=100
  width=10
  eighths=$(( pct * width * 8 / 100 ))
  full=$(( eighths / 8 ))
  rem=$(( eighths % 8 ))
  partial=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')

  bar=''
  for ((i = 0; i < full; i++)); do bar+='█'; done
  if [ "$rem" -gt 0 ] && [ "$full" -lt "$width" ]; then
    bar+="${partial[$rem]}"
    full=$((full + 1))
  fi
  for ((i = full; i < width; i++)); do bar+='░'; done

  c=$(heat "$pct")
  parts+=("${c}${bar}${R} ${c}$(printf '%3d' "$pct")%${R}")
fi

# --- git branch --------------------------------------------------------------
if [ -n "$cwd" ]; then
  # --no-optional-locks so the statusline never blocks or writes the index.
  g() { git --no-optional-locks -C "$cwd" "$@" 2>/dev/null; }
  branch=$(g branch --show-current)
  if [ -z "$branch" ]; then
    # Detached HEAD: fall back to the short sha.
    sha=$(g rev-parse --short HEAD) && [ -n "$sha" ] && branch="@$sha"
  fi
  if [ -n "$branch" ]; then
    # Name the repo from the shared git dir, not the toplevel, so a linked
    # worktree still shows the repo's name rather than the worktree folder's.
    common=$(g rev-parse --path-format=absolute --git-common-dir)
    repo=$(basename "$(dirname "$common")")
    # Tracked-file changes only; skipping untracked keeps this cheap on big repos.
    dirty=''
    [ -n "$(g status --porcelain --untracked-files=no | head -c 1)" ] && dirty="${YELLOW}*${R}"

    # Ahead/behind upstream; a branch with no upstream has never been pushed.
    sync=''
    if counts=$(g rev-list --left-right --count '@{upstream}...HEAD'); then
      read -r behind ahead <<< "$counts"
      [ "$ahead" -gt 0 ] && sync+=" ${GREEN}↑${ahead}${R}"
      [ "$behind" -gt 0 ] && sync+=" ${YELLOW}↓${behind}${R}"
    elif [ "${branch:0:1}" != "@" ]; then
      sync=" ${DIM}unpushed${R}"
    fi

    pr=$(cached "pr:$common:$branch" 300 sh -c 'cd "$1" && gh pr view --json number -q .number' _ "$cwd")
    [ -n "$pr" ] && pr=" ${DIM}#${R}${BRANCH_C}${pr}${R}"

    parts+=("${B}${repo}${R} ${DIM}⎇ ${R}${BRANCH_C}${branch}${R}${dirty}${sync}${pr}")

    # --- ddev: only for repos that have a DDEV project ------------------------
    top=$(g rev-parse --show-toplevel)
    if [ -f "$top/.ddev/config.yaml" ]; then
      project=$(sed -n 's/^name:[[:space:]]*//p' "$top/.ddev/config.yaml" | head -1)
      state=$(cached "ddev:$project" 30 docker ps --filter "name=^ddev-${project}-web\$" --format '{{.Status}}')
      if [ "${state:0:2}" = "Up" ]; then
        parts+=("${GREEN}●${R} ${DIM}ddev${R}")
      else
        parts+=("${RED}○${R} ${DIM}ddev${R}")
      fi
    fi
  fi
fi

# --- rate-limit windows -------------------------------------------------------
# The payload exposes only 5-hour and 7-day usage windows (used_percentage) —
# there is no dollar-based "credit balance" field, so remaining-% of these
# windows is the closest available proxy for "how much credit is left".
if [ -n "$five" ]; then
  fpct=$(printf '%.0f' "$five")
  fleft=$(( 100 - fpct ))
  [ "$fleft" -lt 0 ] && fleft=0
  parts+=("${DIM}5h${R} $(heat "$fpct")${fleft}%${R}${DIM} left${R}")
fi

if [ -n "$week" ]; then
  wpct=$(printf '%.0f' "$week")
  wleft=$(( 100 - wpct ))
  [ "$wleft" -lt 0 ] && wleft=0
  parts+=("${DIM}7d${R} $(heat "$wpct")${wleft}%${R}${DIM} left${R}")
fi

# --- session cost --------------------------------------------------------------
if [ -n "$cost" ]; then
  parts+=("${DIM}\$${R}$(printf '%.2f' "$cost")")
fi

# --- join --------------------------------------------------------------------
out=''
for i in "${!parts[@]}"; do
  [ "$i" -gt 0 ] && out+="$SEP"
  out+="${parts[$i]}"
done
printf '%s\n' "$out"
