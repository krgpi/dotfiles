#!/bin/bash

# フロートウィンドウの大きさをその場で整える（skhd から呼ばれる）
# 高さはディスプレイいっぱいにし、幅は COLS 分割の段階で決める
#
# タイル中のウィンドウに対して押したときは先にフロートへ切り替える
# （サイズを変えたい＝タイルから外したい、なので）
#
# 位置とサイズは --move / --resize ではなく --grid で指定する。
# メニューバーと Dock を除いた領域を yabai 側が見てくれるため

COLS=12
MIN_SPAN=3

action="$1"

win=$(yabai -m query --windows --window 2>/dev/null)
[ -n "$win" ] || exit 0

if [ "$(echo "$win" | jq -r '."is-floating"')" != "true" ]; then
  yabai -m window --toggle float || exit 0
  win=$(yabai -m query --windows --window)
fi

display=$(yabai -m query --displays --display 2>/dev/null)
[ -n "$display" ] || exit 0

dx=$(echo "$display" | jq '.frame.x | floor')
dw=$(echo "$display" | jq '.frame.w | floor')
cell=$(( dw / COLS ))
[ "$cell" -gt 0 ] || exit 0

wx=$(echo "$win" | jq '.frame.x | floor')
ww=$(echo "$win" | jq '.frame.w | floor')

span=$(( (ww + cell / 2) / cell ))
col=$(( (wx - dx + cell / 2) / cell ))
center=1

case "$action" in
  narrower) span=$(( span - 1 )) ;;
  wider)    span=$(( span + 1 )) ;;
  half)     span=$(( COLS / 2 )) ;;
  full)     span=$COLS ;;
  height)   center=0 ;;
  *) exit 0 ;;
esac

[ "$span" -lt "$MIN_SPAN" ] && span=$MIN_SPAN
[ "$span" -gt "$COLS" ] && span=$COLS
[ "$center" -eq 1 ] && col=$(( (COLS - span) / 2 ))
[ "$col" -lt 0 ] && col=0
[ $(( col + span )) -gt "$COLS" ] && col=$(( COLS - span ))

yabai -m window --grid "1:$COLS:$col:0:$span:1"
