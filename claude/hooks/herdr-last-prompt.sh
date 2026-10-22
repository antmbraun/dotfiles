#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook: show the latest prompt under the space's name in herdr's sidebar
# (the $last_prompt token in [ui.sidebar.spaces] rows). Never blocks or fails the prompt.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

[ -n "${HERDR_WORKSPACE_ID:-}" ] && command -v herdr >/dev/null || exit 0

# One line, whitespace collapsed; the sidebar truncates whatever doesn't fit.
prompt="$(jq -r '.prompt // empty' | tr '\n\t' '  ' | tr -s ' ' | sed 's/^ //' | cut -c1-200)"
[ -n "$prompt" ] || exit 0

herdr workspace report-metadata "$HERDR_WORKSPACE_ID" --source claude-last-prompt \
  --token "last_prompt=$prompt" >/dev/null 2>&1 || true
exit 0
