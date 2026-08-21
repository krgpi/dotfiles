#!/bin/bash

# 次のペインへ移動する（prefix + Tab から呼ばれる）
# サイドバーは表示専用なので巡回対象から外す（経由すると after-select-pane フックと二重に動く）
# 狭いとき（ズーム運用中）は移動後もズームを維持する
#
# run-shell に渡される TMUX_PANE はクライアントが今見ているペインとは限らないため、
# 対象はクライアントのセッション経由で解決する

WIDTH_THRESHOLD=120  # tmux-responsive-layout.sh と揃える

target="$(tmux display-message -p '#{client_session}' 2>/dev/null):"
current="$(tmux display-message -p -t "$target" '#{pane_id}' 2>/dev/null)"

next="$(tmux list-panes -t "$target" -F '#{pane_id}|#{@sidebar}' 2>/dev/null | awk -F'|' -v cur="$current" '
  $2 != "1" { n++; id[n] = $1; if ($1 == cur) idx = n }
  END { if (n > 0) print (idx == 0 || idx == n) ? id[1] : id[idx + 1] }')"

[ -n "$next" ] || exit 0
tmux select-pane -t "$next"

width=$(tmux display-message -p '#{client_width}' 2>/dev/null)
if [ -n "$width" ] && [ "$width" -lt "$WIDTH_THRESHOLD" ]; then
  zoomed=$(tmux display-message -p -t "$target" '#{window_zoomed_flag}' 2>/dev/null)
  [ "$zoomed" = "1" ] || tmux resize-pane -Z -t "$next"
fi

tmux refresh-client -S 2>/dev/null || true
