#!/bin/bash

# tmux セッション/ペイン一覧サイドバー
# hookからのSIGUSR1で即座に再描画。フォールバック30秒。
# 数字キーでセッション切り替え可能。

# ペインタイトルを固定（pane-title-changed hookの無限ループ防止）
printf '\033]2;sidebar\033\\'
# マウスレポーティングを無効化（マウスのエスケープシーケンスがstdinに流れ込むのを防ぐ）
printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'

session_count=0

render() {
  # clearの代わりにカーソルをホームへ移動+画面消去（タイトル変更を避ける）
  printf '\033[H\033[2J'
  current_session=$(tmux display-message -p '#S' 2>/dev/null) || exit 0

  printf "\033[1mSessions\033[0m\n"

  session_count=0
  while IFS='|' read -r name attached; do
    ((session_count++))
    if [ "$name" = "$current_session" ]; then
      printf "\033[36;1m%d▶%s\033[0m\n" "$session_count" "$name"
    elif [ "$attached" -ge 1 ] 2>/dev/null; then
      printf "\033[90m%d\033[0m %s\n" "$session_count" "$name"
    else
      printf "\033[90m%d %s\033[0m\n" "$session_count" "$name"
    fi
  done < <(tmux list-sessions -F '#{session_name}|#{session_attached}')

  printf "\n\033[1m%s\033[0m\n" "$current_session"

  while IFS='|' read -r pane_id cmd title active; do
    # Claude Code 入力待ちフラグの確認
    if [ -f "/tmp/claude-waiting-${pane_id}" ]; then
      waiting=1
    else
      waiting=0
    fi

    if [ "$active" = "1" ]; then
      if [ "$waiting" = "1" ]; then
        printf "\033[32;1m▶%s \033[33;1m!\033[0m\n" "$cmd"
      else
        printf "\033[32;1m▶%s\033[0m\n" "$cmd"
      fi
    else
      if [ "$waiting" = "1" ]; then
        printf " %s \033[33;1m!\033[0m\n" "$cmd"
      else
        printf " %s\n" "$cmd"
      fi
    fi
    # pane_title がコマンド名と異なる場合はステータスとして表示
    if [ -n "$title" ] && [ "$title" != "$cmd" ]; then
      printf "\033[90m %.8s\033[0m\n" "$title"
    fi
  done < <(tmux list-panes -t "$current_session" -F '#{pane_id}|#{pane_current_command}|#{pane_title}|#{pane_active}')
}

# SIGUSR1 で read を中断して即座に再描画
trap '' USR1

while true; do
  render
  # 30秒待機（hookのSIGUSR1で即中断される）。数字キーでセッション切り替え。
  if read -t 30 -n 1 key 2>/dev/null; then
    if [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "$session_count" ]; then
      target=$(tmux list-sessions -F '#{session_name}' | sed -n "${key}p")
      [ -n "$target" ] && tmux switch-client -t "$target"
    fi
    # 入力バッファに残ったエスケープシーケンスを捨てる
    read -t 0.1 -n 100 _discard 2>/dev/null
  fi
done
