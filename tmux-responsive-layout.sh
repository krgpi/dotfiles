#!/bin/bash

# 端末幅に応じてレイアウトを自動で切り替える
# client-resized / client-attached フックから呼ばれる
#
# 端末幅が WIDTH_THRESHOLD 未満（狭い）のとき:
#   - 現在のウィンドウをズームして1ペインだけ全画面表示する（サイドバーもズームで隠れる）
#   - ステータスを2行にしてペイン切り替えバー（2行目）を表示する
# 端末幅が WIDTH_THRESHOLD 以上（広い）のとき:
#   - ズームを解除して通常の複数ペインレイアウト（サイドバー + 作業ペイン）に戻す
#   - ステータスを1行に戻してペインバーを隠す

WIDTH_THRESHOLD=120  # この幅（カラム数）未満を「狭い」とみなす。サイドバーの幅を含む

width=$(tmux display-message -p '#{client_width}' 2>/dev/null) || exit 0
[ -z "$width" ] && exit 0

# run-shell の既定ターゲットはクライアントが見ているペインとは限らないので、
# クライアントのセッション経由で解決する
target="$(tmux display-message -p '#{client_session}' 2>/dev/null):"

pane_count=$(tmux display-message -p -t "$target" '#{window_panes}' 2>/dev/null)
zoomed=$(tmux display-message -p -t "$target" '#{window_zoomed_flag}' 2>/dev/null)
status=$(tmux show-option -gv status 2>/dev/null)

if [ "$width" -lt "$WIDTH_THRESHOLD" ]; then
  # 狭い: ペイン切り替えバーを出す（ステータス2行）
  [ "$status" = "2" ] || tmux set-option -g status 2
  # 複数ペインかつ未ズームならズームして1ペイン表示にする
  if [ "$pane_count" -gt 1 ] && [ "$zoomed" != "1" ]; then
    # サイドバーをズームしても意味がないので、その場合は隣のペインへ移ってからズームする
    if [ "$(tmux display-message -p -t "$target" '#{@sidebar}' 2>/dev/null)" = "1" ]; then
      tmux select-pane -t "$target.+"
    fi
    tmux resize-pane -Z -t "$target"
  fi
else
  # 広い: ペインバーを隠す（ステータス1行）
  [ "$status" = "on" ] || tmux set-option -g status on
  # ズーム中なら解除して複数ペインに戻す
  if [ "$zoomed" = "1" ]; then
    tmux resize-pane -Z -t "$target"
  fi
fi

tmux refresh-client -S 2>/dev/null || true
