#!/bin/bash

# ステータスバーの表示順(N番目)でセッションを切り替える
# 使い方: tmux-switch-session.sh <番号>

num="${1:-}"
[ -z "$num" ] && exit 1

target=$(tmux list-sessions -F '#{session_name}' | sed -n "${num}p")
[ -n "$target" ] && tmux switch-client -t "$target" \; refresh-client -S
