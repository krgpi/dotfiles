#!/bin/bash

# 今いるスペースのタイル表示を切り替える（skhd から呼ばれる）
#
# 既定は float（.yabairc の layout）。bsp にしたスペースは、もう一度押すか
# yabai を再起動するまでタイルされ続ける

layout=$(yabai -m query --spaces --space 2>/dev/null | jq -r '.type') || exit 0

if [ "$layout" = "bsp" ]; then
  yabai -m space --layout float
else
  yabai -m space --layout bsp
  "$(dirname "$0")/yabai-solo-padding.sh"
fi
