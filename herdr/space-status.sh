#!/usr/bin/env bash
# Live status board for a herdr space: branch, PR, multidev and git changes for every repo the space's
# Claude session has worked in (plus the main pane's own repo).
# Usage: space-status.sh <main_pane_id>
set -uo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

MAIN_PANE="${1:?usage: space-status.sh <main_pane_id>}"
GIT_EVERY=3   # seconds between git refreshes
GH_EVERY=60   # seconds between GitHub refreshes (rate limits)

e=$'\e' nl=$'\n'
bold="$e[1m" dim="$e[2m" green="$e[32m" yellow="$e[33m" red="$e[31m" cyan="$e[36m" reset="$e[0m"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/herdr-space-status/${MAIN_PANE//:/_}"
mkdir -p "$CACHE_DIR"

# Re-exec when this script is edited, so running boards pick up changes.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
self_mtime="$(stat -f %m "$SELF")"

# OSC 8 hyperlink: clickable in herdr (ctrl+click) and Ghostty, even when the label isn't the full URL.
link() { printf '%s' "$e]8;;$1$e\\$2$e]8;;$e\\"; }

# Pantheon site comes from the repo's ddev provider config, e.g. "project: b2b-mb.live" -> b2b-mb.
pantheon_site() {
  sed -nE 's/^[[:space:]]*project:[[:space:]]*([a-z0-9-]+)\.[a-z]+[[:space:]]*$/\1/p' "$1/.ddev/providers/pantheon.yaml" 2>/dev/null | head -1
}

cache_file() { printf '%s/%s' "$CACHE_DIR" "$(printf '%s' "$1" | shasum | cut -c1-16)"; }

# Cached `gh pr view` JSON for a repo+branch, refreshed every GH_EVERY seconds.
pr_json() {
  local root=$1 branch=$2 f age
  f="$(cache_file "pr:$root@$branch")"
  age=$GH_EVERY
  [ -f "$f" ] && age=$(( $(date +%s) - $(stat -f %m "$f") ))
  if [ "$age" -ge "$GH_EVERY" ]; then
    (cd "$root" && gh pr view "$branch" --json number,url,state,isDraft,reviewDecision,statusCheckRollup 2>/dev/null) >"$f.tmp" || : >"$f.tmp"
    mv "$f.tmp" "$f"
  fi
  cat "$f"
}

# Claude usage line (herdr/usage.sh), shared by every board and refreshed in the background every
# GH_EVERY seconds: ccusage takes a couple of seconds, which would stall the board.
USAGE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/herdr-space-status/usage"
usage_line() {
  local age=$GH_EVERY
  [ -f "$USAGE_FILE" ] && age=$(( $(date +%s) - $(stat -f %m "$USAGE_FILE") ))
  if [ "$age" -ge "$GH_EVERY" ]; then
    touch "$USAGE_FILE" # so the other boards don't start their own refresh
    ( "$(dirname "$SELF")/usage.sh" >"$USAGE_FILE.tmp.$$" 2>/dev/null && mv "$USAGE_FILE.tmp.$$" "$USAGE_FILE" || rm -f "$USAGE_FILE.tmp.$$" ) </dev/null >/dev/null 2>&1 &
  fi
  cat "$USAGE_FILE"
}

# Transcript of the Claude session in the main pane, if any.
transcript_for() {
  local session=$1 f
  f="$(cache_file "transcript:$session")"
  if [ ! -s "$f" ] || [ ! -f "$(cat "$f")" ]; then
    ls "$HOME"/.claude/projects/*/"$session.jsonl" "$HOME"/.claude-personal/projects/*/"$session.jsonl" 2>/dev/null | head -1 >"$f"
  fi
  cat "$f"
}

# Git repos the session worked in, most recently used first: files it edited, and git/gh commands it ran.
# Read-only exploration (reads, greps) doesn't count. Rescanned only when the transcript grows.
session_repos() {
  local transcript=$1 f size
  f="$(cache_file "repos:$transcript")"
  size="$(stat -f %z "$transcript" 2>/dev/null)"
  if [ "$(head -1 "$f" 2>/dev/null)" != "$size" ]; then
    {
      echo "$size"
      jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
             | if (.name | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) then (.input.file_path // .input.notebook_path // empty)
               elif .name == "Bash" then (.input.command // "" | select(test("(^|[;&|(]|\\s)(git\\s|gh\\s+pr\\s+(create|edit|merge|ready|checkout))")))
               else empty end' "$transcript" 2>/dev/null |
        sed -E "s#(^|[[:space:]\"'=])~/#\\1$HOME/#g; s#\\\$HOME/#$HOME/#g" |
        grep -oE "$HOME/[A-Za-z0-9._/-]+" |
        awk -F/ -v OFS=/ '{ n = NF < 8 ? NF : 8; s = $1; for (i = 2; i <= n; i++) s = s OFS $i; last[s] = NR }
                          END { for (s in last) print last[s] "\t" s }' |
        sort -rn | cut -f2 |
        while read -r p; do
          while [ -n "$p" ] && [ ! -d "$p" ]; do p="${p%/*}"; done
          [ -n "$p" ] && git -C "$p" rev-parse --show-toplevel 2>/dev/null || true
        done | awk '!seen[$0]++'
    } >"$f.tmp"
    mv "$f.tmp" "$f"
  fi
  tail -n +2 "$f"
}

# Everything the session typed into tools, plus the branches Claude Code recorded it on. Used to
# tell which branches (and so which PRs) belong to this session. Rebuilt when the transcript grows.
session_corpus() {
  local transcript=$1 f size
  f="$(cache_file "corpus:$transcript")"
  size="$(stat -f %z "$transcript" 2>/dev/null)"
  if [ "$(head -1 "$f" 2>/dev/null)" != "$size" ]; then
    {
      echo "$size"
      jq -r '(.gitBranch // empty),
             (select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .input | tostring)' \
        "$transcript" 2>/dev/null
    } >"$f.tmp"
    mv "$f.tmp" "$f"
  fi
  printf '%s' "$f"
}

# Cached list of your open PRs in a repo.
my_prs_json() {
  local root=$1 f age
  f="$(cache_file "myprs:$root")"
  age=$GH_EVERY
  [ -f "$f" ] && age=$(( $(date +%s) - $(stat -f %m "$f") ))
  if [ "$age" -ge "$GH_EVERY" ]; then
    (cd "$root" && gh pr list --author @me --state open --json headRefName 2>/dev/null) >"$f.tmp" || echo '[]' >"$f.tmp"
    mv "$f.tmp" "$f"
  fi
  cat "$f"
}

# Branches with PRs to show for a repo: the checked-out one (when the session used it, since other sessions
# share the checkout), plus your open PRs whose branch the session used. With no session, just the checkout.
pr_branches() {
  local root=$1 current=$2 corpus=$3 b
  if [ -z "$corpus" ]; then
    [ -n "$current" ] && echo "$current"
    return 0
  fi
  [ -n "$current" ] && grep -qF -- "$current" "$corpus" && echo "$current"
  my_prs_json "$root" | jq -r '.[].headRefName' | while read -r b; do
    [ "$b" != "$current" ] && grep -qF -- "$b" "$corpus" && echo "$b"
  done
  return 0
}

render_pr() {
  local root=$1 json=$2 label=$3 out="" number url summary site md
  number="$(jq -r '.number' <<<"$json")"
  url="$(jq -r '.url' <<<"$json")"
  summary="$(jq -r --arg g "$green" --arg y "$yellow" --arg r "$red" --arg x "$reset" '
    def checks: [.statusCheckRollup[]? | (.conclusion // .state // "PENDING")] as $c
      | if ($c | length) == 0 then ""
        elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT") then "\($r)checks failing\($x)"
        elif all($c[]; . == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED") then "\($g)checks passing\($x)"
        else "\($y)checks running\($x)" end;
    (if .isDraft then "draft" else (.state | ascii_downcase) end)
    + (if .reviewDecision then " · \(.reviewDecision | ascii_downcase | gsub("_"; " "))" else "" end)
    + (checks as $k | if $k == "" then "" else " · \($k)" end)' <<<"$json")"
  out+="  PR        $(link "$url" "${url#https://}")$nl"
  [ -n "$label" ] && out+="            ${cyan}$label${reset}$nl"
  out+="            $summary$nl"
  site="$(pantheon_site "$root")"
  # Multidevs are torn down once a PR is merged or closed.
  if [ -n "$site" ] && [ "$(jq -r '.state' <<<"$json")" = "OPEN" ]; then
    md="https://pr-$number-$site.pantheonsite.io"
    out+="  Multidev  $(link "$md" "${md#https://}")$nl"
  fi
  printf '%s' "$out"
}

render_repo() {
  local root=$1 corpus=$2 out="" branch ahead_behind behind ahead json changes count b shown=0
  branch="$(git -C "$root" branch --show-current 2>/dev/null)"
  out+="${bold}$(basename "$root")${reset} ${cyan}${branch:-detached}${reset}"
  if ahead_behind="$(git -C "$root" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"; then
    read -r behind ahead <<<"$ahead_behind"
    [ "$ahead" -gt 0 ] && out+=" ${green}↑$ahead${reset}"
    [ "$behind" -gt 0 ] && out+=" ${yellow}↓$behind${reset}"
  fi
  out+="$nl"

  # The checked-out branch's PR, then any other of your PRs this session worked on (labelled with their branch).
  while read -r b; do
    [ -n "$b" ] || continue
    json="$(pr_json "$root" "$b")"
    [ -n "$json" ] || continue
    if [ "$b" = "$branch" ]; then out+="$(render_pr "$root" "$json" "")$nl"; else out+="$(render_pr "$root" "$json" "$b")$nl"; fi
    shown=1
  done <<<"$(pr_branches "$root" "$branch" "$corpus")"
  [ "$shown" -eq 1 ] || out+="  PR        ${dim}none${reset}$nl"

  changes="$(git -C "$root" -c color.status=always status --short 2>/dev/null)"
  count="$(git -C "$root" status --short 2>/dev/null | wc -l | tr -d ' ')"
  if [ -n "$changes" ]; then
    out+="  Changes   ${dim}($count)${reset}$nl$(sed 's/^/    /' <<<"$changes")$nl"
  else
    out+="  Changes   ${dim}clean${reset}$nl"
  fi
  printf '%s' "$out"
}

while true; do
  pane="$(herdr pane get "$MAIN_PANE" 2>/dev/null)"
  cwd="$(jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty' <<<"$pane")"
  [ -n "$cwd" ] || exit 0 # main pane is gone; close with it

  # A Claude session's statusline records its real working dir (e.g. after entering a worktree).
  session="$(jq -r 'select(.result.pane.agent == "claude") | .result.pane.agent_session.value // empty' <<<"$pane")"
  session_cwd_file="${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-cwd/$session"
  if [ -n "$session" ] && [ -f "$session_cwd_file" ]; then
    session_cwd="$(cat "$session_cwd_file")"
    [ -d "$session_cwd" ] && cwd="$session_cwd"
  fi

  repos="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  corpus=""
  if [ -n "$session" ]; then
    transcript="$(transcript_for "$session")"
    if [ -n "$transcript" ]; then
      repos="$(printf '%s\n%s\n' "$repos" "$(session_repos "$transcript")" | awk 'NF && !seen[$0]++')"
      corpus="$(session_corpus "$transcript")"
    fi
  fi

  out=""
  usage="$(usage_line)"
  [ -n "$usage" ] && out+="${dim}${usage}${reset}$nl$nl"
  if [ -z "$repos" ]; then
    out="${dim}${cwd/#$HOME/~}${reset}$nl${nl}no git repos yet$nl"
  else
    while read -r root; do
      [ -n "$out" ] && [ "${out: -2}" != "$nl$nl" ] && out+="$nl"
      out+="$(render_repo "$root" "$corpus")$nl"
    done <<<"$repos"
  fi

  printf '%s' "$e[H$e[2J$out"
  sleep "$GIT_EVERY"
  [ "$(stat -f %m "$SELF" 2>/dev/null)" = "$self_mtime" ] || exec bash "$SELF" "$MAIN_PANE"
done
