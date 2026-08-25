#!/bin/bash

# タイル中のウィンドウが1枚だけのとき、左右に余白を足して幅を絞る（yabai の signal と skhd から呼ばれる）
#
# 余白そのものではなく「この幅までに収める」という上限から逆算するので、
# 内蔵ディスプレイと外部ディスプレイで見え方が変わらない

MAX_WIDTH="${YABAI_SOLO_MAX_WIDTH:-1600}"
PADDING=12  # .yabairc の *_padding と揃える

space=$(yabai -m query --spaces --space 2>/dev/null) || exit 0
[ "$(echo "$space" | jq -r '.type')" = "bsp" ] || exit 0

count=$(yabai -m query --windows --space 2>/dev/null |
  jq '[.[] | select(."is-floating" == false and ."is-minimized" == false and ."is-hidden" == false)] | length')
[ -n "$count" ] || exit 0

side=$PADDING
if [ "$count" -le 1 ]; then
  width=$(yabai -m query --displays --display 2>/dev/null | jq '.frame.w | floor')
  [ -n "$width" ] || exit 0
  side=$(( (width - MAX_WIDTH) / 2 ))
  [ "$side" -lt "$PADDING" ] && side=$PADDING
fi

yabai -m space --padding abs:$PADDING:$PADDING:$side:$side
