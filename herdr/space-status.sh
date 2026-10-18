#!/usr/bin/env bash
# Live status board for a herdr space: branch, PR, multidev and git changes for the repo the space's main pane is in.
# Usage: space-status.sh <main_pane_id>
set -uo pipefail
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

MAIN_PANE="${1:?usage: space-status.sh <main_pane_id>}"
GIT_EVERY=3   # seconds between git refreshes
GH_EVERY=60   # seconds between GitHub refreshes (rate limits)

bold=$'\e[1m' dim=$'\e[2m' green=$'\e[32m' yellow=$'\e[33m' red=$'\e[31m' cyan=$'\e[36m' reset=$'\e[0m'

pr_line="" pr_number="" last_gh=0 last_key=""

# Pantheon site comes from the repo's ddev provider config, e.g. "project: b2b-mb.live" -> b2b-mb.
pantheon_site() {
  sed -nE 's/^[[:space:]]*project:[[:space:]]*([a-z0-9-]+)\.[a-z]+[[:space:]]*$/\1/p' "$1/.ddev/providers/pantheon.yaml" 2>/dev/null | head -1
}

refresh_gh() {
  pr_line="" pr_number=""
  local json
  json="$(cd "$1" && gh pr view --json number,url,state,isDraft,reviewDecision,statusCheckRollup 2>/dev/null)" || return
  pr_number="$(jq -r '.number' <<<"$json")"
  pr_line="$(jq -r --arg g "$green" --arg y "$yellow" --arg r "$red" --arg d "$dim" --arg x "$reset" '
    def checks: [.statusCheckRollup[]? | (.conclusion // .state // "PENDING")] as $c
      | if ($c | length) == 0 then ""
        elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "CANCELLED" or . == "TIMED_OUT") then "\($r)checks failing\($x)"
        elif all($c[]; . == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED") then "\($g)checks passing\($x)"
        else "\($y)checks running\($x)" end;
    "\(.url)\n  \(if .isDraft then "draft" else (.state | ascii_downcase) end)"
    + (if .reviewDecision then " · \(.reviewDecision | ascii_downcase | gsub("_"; " "))" else "" end)
    + (checks as $k | if $k == "" then "" else " · \($k)" end)' <<<"$json")"
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
  root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"

  out=""
  if [ -z "$root" ]; then
    out+="${dim}${cwd/#$HOME/~}${reset}\n\nnot a git repo\n"
  else
    branch="$(git -C "$root" branch --show-current 2>/dev/null)"
    key="$root@$branch"
    now="$(date +%s)"
    if [ "$key" != "$last_key" ] || [ $((now - last_gh)) -ge "$GH_EVERY" ]; then
      refresh_gh "$root"; last_gh="$now"; last_key="$key"
    fi

    out+="${bold}$(basename "$root")${reset} ${cyan}${branch:-detached}${reset}"
    ahead_behind="$(git -C "$root" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"
    if [ -n "$ahead_behind" ]; then
      read -r behind ahead <<<"$ahead_behind"
      [ "$ahead" -gt 0 ] && out+=" ${green}↑$ahead${reset}"
      [ "$behind" -gt 0 ] && out+=" ${yellow}↓$behind${reset}"
    fi
    out+="\n\n${bold}PR${reset}\n"
    if [ -n "$pr_line" ]; then out+="  $pr_line\n"; else out+="  ${dim}none${reset}\n"; fi

    site="$(pantheon_site "$root")"
    if [ -n "$site" ]; then
      out+="\n${bold}Multidev${reset}\n"
      if [ -n "$pr_number" ]; then out+="  https://pr-$pr_number-$site.pantheonsite.io\n"; else out+="  ${dim}none (needs a PR)${reset}\n"; fi
    fi

    changes="$(git -C "$root" -c color.status=always status --short 2>/dev/null)"
    count="$(git -C "$root" status --short 2>/dev/null | wc -l | tr -d ' ')"
    out+="\n${bold}Changes${reset} ${dim}($count)${reset}\n"
    if [ -n "$changes" ]; then out+="$(sed 's/^/  /' <<<"$changes")\n"; else out+="  ${dim}clean${reset}\n"; fi
  fi

  printf '\e[H\e[2J%b' "$out"
  sleep "$GIT_EVERY"
done
