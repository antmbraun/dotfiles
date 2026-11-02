#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook: show the latest prompt on this Claude's row in herdr's Agents panel
# (the $last_prompt token in [ui.sidebar.agents] rows). Never blocks or fails the prompt.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

[ -n "${HERDR_PANE_ID:-}" ] && command -v herdr >/dev/null || exit 0

# One line, whitespace collapsed; the sidebar truncates whatever doesn't fit.
prompt="$(jq -r '.prompt // empty' | tr '\n\t' '  ' | tr -s ' ' | sed 's/^ //' | cut -c1-200)"
# Background-task notifications arrive as prompts too; they aren't mine.
case "$prompt" in "" | "<task-notification>"*) exit 0 ;; esac

herdr pane report-metadata "$HERDR_PANE_ID" --source claude-last-prompt \
  --token "last_prompt=$prompt" >/dev/null 2>&1 || true
exit 0
