#!/bin/bash

# セッション切り替え時のClaude既読処理
# after-select-pane hook から呼ばれる
# Claudeペインのフラグを削除し、既読ロックを作成する
# 非Claudeペインにはロックを作らない

PANE_ID="${1:-}"
[ -z "$PANE_ID" ] && exit 0

FLAG_FILE="/tmp/claude-waiting-${PANE_ID}"
READ_LOCK="/tmp/claude-read-${PANE_ID}"

# フラグがあれば削除（Claudeの未読を既読にする）
if [ -f "$FLAG_FILE" ]; then
  rm -f "$FLAG_FILE"
  # Claudeペインだったので既読ロックを作成（idle_prompt再発火対策）
  touch "$READ_LOCK"
fi

tmux refresh-client -S 2>/dev/null || true
