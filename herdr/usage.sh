#!/usr/bin/env bash
# Claude usage for herdr's tab bar: today's and this month's spend across both accounts (from ccusage), plus each
# account's 5-hour and 7-day plan usage as last reported by ~/dotfiles/claude/statusline-command.sh.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
USAGE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-usage"

parts=()

# One ccusage run over the month gives both today's and the month's spend. ccusage prices the
# conversation logs at API rates, so it's an estimate: the billed spend and limit in /usage aren't
# available to scripts.
read -r today month <<<"$(cd /tmp && CLAUDE_CONFIG_DIR="$HOME/.claude,$HOME/.claude-personal" \
  npx -y ccusage@20.0.40 daily --json --offline --since "$(date +%Y%m01)" 2>/dev/null |
  jq -r --arg d "$(date +%Y-%m-%d)" '"\([.daily[] | select((.period // .date) == $d) | .totalCost] | add // 0) \(.totals.totalCost // empty)"')"
[ -n "$month" ] && parts+=("today \$$(printf '%.2f' "$today")" "$(date +%b) ~\$$(printf '%.0f' "$month") est")

now="$(date +%s)"
for f in "$USAGE_DIR"/*.json; do
  [ -f "$f" ] || continue
  account="$(basename "$f" .json)"
  # A window that has reset since the last report shows 0, not the stale number.
  usage="$(jq -r --argjson now "$now" '
    def pct(w): if w == null then empty
      elif (w.resets_at // 0) > 0 and w.resets_at < $now then "0%"
      else "\(w.used_percentage | round)%" end;
    [("5h " + pct(.five_hour)), ("7d " + pct(.seven_day))] | join(" ")' "$f" 2>/dev/null)"
  [ -n "$usage" ] && parts+=("$account $usage")
done

out=""
for p in "${parts[@]}"; do out+="${out:+ · }$p"; done
printf '%s\n' "$out"
