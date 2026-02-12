#!/bin/bash
# Claude Code -> VS Code notification helper
# Usage: vscode-notify.sh "title" "message"
#
# Uses terminal-notifier to show macOS notifications with VS Code's icon.
# Clicking the notification activates VS Code and focuses the panel.

TITLE="${1:-Claude Code}"
MESSAGE="${2:-通知があります}"

terminal-notifier \
  -title "$TITLE" \
  -message "$MESSAGE" \
  -sender "com.microsoft.VSCode" \
  -open "vscode://command/workbench.action.focusPanel" \
  2>/dev/null || echo "❌ VS Code notification failed" >&2
