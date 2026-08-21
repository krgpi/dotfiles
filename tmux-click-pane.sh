#!/bin/bash

# ペイン切り替えバーのクリック位置からペインを切り替える
# ステータスバー2行目のクリックから mouse_x を受け取って呼ばれる
# 使い方: tmux-click-pane.sh <mouse_x>

mouse_x="${1:-}"
[ -z "$mouse_x" ] && exit 1

posfile="/tmp/tmux-pane-positions"
[ -f "$posfile" ] || exit 1

WIDTH_THRESHOLD=120  # tmux-responsive-layout.sh と揃える

while IFS='|' read -r pane_id start end; do
  [ -z "$pane_id" ] && continue
  if [ "$mouse_x" -ge "$start" ] && [ "$mouse_x" -lt "$end" ]; then
    tmux select-pane -t "$pane_id"
    # 狭い間はズーム運用中なので、選択ペインを再ズームして1ペイン表示を維持する
    # （select-pane でズームは解除されるため）
    width=$(tmux display-message -p '#{client_width}' 2>/dev/null)
    if [ -n "$width" ] && [ "$width" -lt "$WIDTH_THRESHOLD" ]; then
      zoomed=$(tmux display-message -p '#{window_zoomed_flag}' 2>/dev/null)
      [ "$zoomed" = "1" ] || tmux resize-pane -Z -t "$pane_id"
    fi
    tmux refresh-client -S 2>/dev/null || true
    exit 0
  fi
done < "$posfile"
