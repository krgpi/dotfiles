#!/bin/bash

# ステータスバーのクリック位置からセッションを切り替える
# 使い方: tmux-click-session.sh <mouse_x>

mouse_x="${1:-}"
[ -z "$mouse_x" ] && exit 1

posfile="/tmp/tmux-session-positions"
[ -f "$posfile" ] || exit 1

while IFS='|' read -r name start end; do
  [ -z "$name" ] && continue
  if [ "$mouse_x" -ge "$start" ] && [ "$mouse_x" -lt "$end" ]; then
    tmux switch-client -t "$name" \; refresh-client -S
    exit 0
  fi
done < "$posfile"
