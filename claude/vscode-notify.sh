#!/bin/bash
# Claude Code -> VS Code notification helper
# Usage: vscode-notify.sh "title" "message"
#
# Uses terminal-notifier to show macOS notifications.
# Clicking the notification activates VS Code and focuses Claude Code panel via Cmd+Esc.
# Note: Requires accessibility permissions for System Events.

TITLE="${1:-Claude Code}"
MESSAGE="${2:-通知があります}"

terminal-notifier \
  -title "$TITLE" \
  -message "$MESSAGE" \
  -execute "osascript -e 'tell application \"Visual Studio Code\" to activate' -e 'delay 0.5' -e 'tell application \"System Events\" to key code 53 using command down'" \
  2>/dev/null || echo "❌ VS Code notification failed" >&2
