#!/bin/bash

# 端末幅に応じてレイアウトを自動で切り替える
# client-resized / client-attached フックから呼ばれる
#
# 端末幅が WIDTH_THRESHOLD 未満（狭い）のとき:
#   - 現在のウィンドウをズームして1ペインだけ全画面表示する（レイアウト解消）
#   - ステータスを2行にしてペイン切り替えバー（2行目）を表示する
# 端末幅が WIDTH_THRESHOLD 以上（広い）のとき:
#   - ズームを解除して通常の複数ペインレイアウトに戻す
#   - ステータスを1行に戻してペインバーを隠す

WIDTH_THRESHOLD=100  # この幅（カラム数）未満を「狭い」とみなす。好みに応じて調整

width=$(tmux display-message -p '#{client_width}' 2>/dev/null) || exit 0
[ -z "$width" ] && exit 0

pane_count=$(tmux display-message -p '#{window_panes}' 2>/dev/null)
zoomed=$(tmux display-message -p '#{window_zoomed_flag}' 2>/dev/null)
status=$(tmux show-option -gv status 2>/dev/null)

if [ "$width" -lt "$WIDTH_THRESHOLD" ]; then
  # 狭い: ペイン切り替えバーを出す（ステータス2行）
  [ "$status" = "2" ] || tmux set-option -g status 2
  # 複数ペインかつ未ズームならズームして1ペイン表示にする
  if [ "$pane_count" -gt 1 ] && [ "$zoomed" != "1" ]; then
    tmux resize-pane -Z
  fi
else
  # 広い: ペインバーを隠す（ステータス1行）
  [ "$status" = "on" ] || tmux set-option -g status on
  # ズーム中なら解除して複数ペインに戻す
  if [ "$zoomed" = "1" ]; then
    tmux resize-pane -Z
  fi
fi

tmux refresh-client -S 2>/dev/null || true
