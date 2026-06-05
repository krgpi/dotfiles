#!/bin/bash

# 次のペインへ移動する（prefix + Tab から呼ばれる）
# 狭いとき（ズーム運用中）は移動後もズームを維持する

tmux select-pane -t :.+

WIDTH_THRESHOLD=100  # tmux-responsive-layout.sh と揃える

width=$(tmux display-message -p '#{client_width}' 2>/dev/null)
if [ -n "$width" ] && [ "$width" -lt "$WIDTH_THRESHOLD" ]; then
  zoomed=$(tmux display-message -p '#{window_zoomed_flag}' 2>/dev/null)
  [ "$zoomed" = "1" ] || tmux resize-pane -Z
fi

tmux refresh-client -S 2>/dev/null || true
