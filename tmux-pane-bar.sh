#!/bin/bash

# 狭いとき用のペイン切り替えバーを生成する
# status-format[1]（ステータス2行目）から #() で呼び出される
# tmux のフォーマット文字列を出力する
#
# クリック判定用の位置情報（ペインID|開始位置|終了位置）を
# /tmp/tmux-pane-positions に書き出す（tmux-click-pane.sh が参照する）

active=$(tmux display-message -p '#{pane_id}' 2>/dev/null) || exit 0

buf=""
pos=0           # 表示上の文字位置（クリック判定用）
positions=""    # ペインID|開始位置|終了位置 のリスト
idx=0

while IFS='|' read -r pane_id cmd; do
  ((idx++))
  label="${idx}:${cmd}"

  # 表示幅: " label " （前後スペース込み）
  text_width=$(( 1 + ${#label} + 1 ))
  start=$pos

  if [ "$pane_id" = "$active" ]; then
    buf+="#[bg=colour238,fg=cyan,bold] ${label} #[default]"
  else
    buf+="#[bg=colour235,fg=colour245] ${label} #[default]"
  fi

  pos=$(( pos + text_width ))
  positions+="${pane_id}|${start}|${pos}"$'\n'
done < <(tmux list-panes -F '#{pane_id}|#{pane_current_command}' 2>/dev/null)

# クリック判定用の位置情報を書き出す
printf '%s' "$positions" > /tmp/tmux-pane-positions

printf '%s' "$buf"
