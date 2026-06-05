#!/bin/bash

# ステータスバーのクリックを行番号で振り分けるディスパッチャ
# MouseDown1Status / MouseDown1StatusLeft バインドから呼ばれる
# 使い方: tmux-status-click.sh <mouse_status_line> <mouse_x>
#
# line==1（2行目）: ペイン切り替えバー
# それ以外（1行目）: セッション切り替えバー

line="${1:-0}"
mouse_x="${2:-}"
[ -z "$mouse_x" ] && exit 0

if [ "$line" = "1" ]; then
  exec ~/Developer/dotfiles/tmux-click-pane.sh "$mouse_x"
else
  exec ~/Developer/dotfiles/tmux-click-session.sh "$mouse_x"
fi
