#!/bin/bash

# tmux セッション/ペイン一覧サイドバー
# hookからのSIGUSR1で即座に再描画。
# 数字キーでセッション切り替え可能。
# 左下にClaude Codeのイベントログを表示。

# ペインタイトルを固定（pane-title-changed hookの無限ループ防止）
printf '\033]2;sidebar\033\\'
# マウスレポーティングを無効化（マウスのエスケープシーケンスがstdinに流れ込むのを防ぐ）
printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'

session_count=0

# セッション内に待機中ペインがあるか判定
session_has_waiting() {
  local session_name="$1"
  while IFS= read -r pane_id; do
    [ -f "/tmp/claude-waiting-${pane_id}" ] && return 0
  done < <(tmux list-panes -t "$session_name" -F '#{pane_id}' 2>/dev/null)
  return 1
}

render() {
  # clearの代わりにカーソルをホームへ移動+画面消去（タイトル変更を避ける）
  printf '\033[H\033[2J'
  current_session=$(tmux display-message -p '#S' 2>/dev/null) || exit 0

  printf "\033[1mSessions\033[0m\n"

  session_count=0
  while IFS='|' read -r name attached; do
    ((session_count++))
    # セッション内の待機通知を確認
    if session_has_waiting "$name"; then
      notify=" \033[5;33;1m●\033[0m"
    else
      notify=""
    fi

    if [ "$name" = "$current_session" ]; then
      printf "\033[36;1m%d▶%s\033[0m${notify}\n" "$session_count" "$name"
    elif [ "$attached" -ge 1 ] 2>/dev/null; then
      printf "\033[37m%d\033[0m %s${notify}\n" "$session_count" "$name"
    else
      printf "\033[2m%d %s\033[0m${notify}\n" "$session_count" "$name"
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
        printf "\033[32;1m▶%s \033[5;33;1m●\033[0m\n" "$cmd"
      else
        printf "\033[32;1m▶%s\033[0m\n" "$cmd"
      fi
    else
      if [ "$waiting" = "1" ]; then
        printf " \033[37m%s\033[0m \033[5;33;1m●\033[0m\n" "$cmd"
      else
        printf " \033[37m%s\033[0m\n" "$cmd"
      fi
    fi
    # pane_title がコマンド名と異なる場合はステータスとして表示
    if [ -n "$title" ] && [ "$title" != "$cmd" ]; then
      printf "\033[2m %.8s\033[0m\n" "$title"
    fi
  done < <(tmux list-panes -t "$current_session" -F '#{pane_id}|#{pane_current_command}|#{pane_title}|#{pane_active}')

  # --- ログ表示（左下） ---
  local pane_height
  pane_height=$(tmux display-message -p '#{pane_height}' 2>/dev/null)

  # 現在のセッションに属するペインのログファイルを集約
  local merged_log="/tmp/claude-sidebar-merged-$$"
  : > "$merged_log"
  while IFS= read -r pane_id; do
    local logfile="/tmp/claude-sidebar-log-${pane_id}"
    [ -f "$logfile" ] && cat "$logfile" >> "$merged_log"
  done < <(tmux list-panes -t "$current_session" -F '#{pane_id}' 2>/dev/null)

  local log_total
  log_total=$(wc -l < "$merged_log" 2>/dev/null)
  log_total=${log_total// /}

  if [ "$log_total" -gt 0 ] 2>/dev/null; then
    # ログ表示に使える行数（ペイン高さの残り、最低1行）
    local session_lines pane_lines total_used log_area
    session_lines=$(tmux list-sessions 2>/dev/null | wc -l)
    pane_lines=$(tmux list-panes -t "$current_session" 2>/dev/null | wc -l)
    total_used=$((1 + session_lines + 2 + pane_lines * 2 + 1))
    log_area=$((pane_height - total_used - 1))
    [ "$log_area" -lt 1 ] && log_area=1

    # 下部に配置
    local log_start=$((pane_height - log_area))
    printf '\033[%d;1H' "$log_start"
    printf "\033[2m"
    tail -"$log_area" "$merged_log" | while IFS= read -r line; do
      printf "%.10s\n" "$line"
    done
    printf "\033[0m"
  fi
  rm -f "$merged_log"
}

# SIGUSR1 で read を中断して即座に再描画
trap '' USR1

while true; do
  render
  # SIGUSR1 で即中断される無期限待機。数字キーでセッション切り替え。
  # フォールバックポーリングは無効化（SIGUSR1のみで更新）
  # if read -t 30 -n 1 key 2>/dev/null; then
  if read -n 1 key 2>/dev/null; then
    if [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "$session_count" ]; then
      target=$(tmux list-sessions -F '#{session_name}' | sed -n "${key}p")
      [ -n "$target" ] && tmux switch-client -t "$target"
    fi
    # 入力バッファに残ったエスケープシーケンスを捨てる
    read -t 0.1 -n 100 _discard 2>/dev/null
  fi
done
