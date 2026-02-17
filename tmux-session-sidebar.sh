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

# セッション内のClaude Codeペインの状態インジケーターを生成
# 動作中=○（白丸）、人間の入力待ち=●（黒丸、点滅黄色）
session_claude_indicators() {
  local session_name="$1"
  local indicators=""
  while IFS='|' read -r pane_id cmd; do
    [ "$cmd" = "claude" ] || continue
    if [ -f "/tmp/claude-waiting-${pane_id}" ]; then
      indicators+="\033[5;33;1m●\033[0m"
    else
      indicators+="○"
    fi
  done < <(tmux list-panes -t "$session_name" -F '#{pane_id}|#{pane_current_command}' 2>/dev/null)
  echo -n "$indicators"
}

render() {
  local buf=""
  current_session=$(tmux display-message -p '#S' 2>/dev/null) || exit 0

  buf+="\033[1mSessions\033[0m\n"

  session_count=0
  while IFS='|' read -r name attached; do
    ((session_count++))
    # セッション内のClaude Code状態インジケーター
    local ci
    ci=$(session_claude_indicators "$name")

    if [ -n "$ci" ]; then
      notify=" ${ci}"
    else
      notify=""
    fi

    if [ "$name" = "$current_session" ]; then
      buf+="$(printf "\033[36;1m%d▶%s\033[0m${notify}" "$session_count" "$name")\n"
    elif [ "$attached" -ge 1 ] 2>/dev/null; then
      buf+="$(printf "\033[37m%d\033[0m %s${notify}" "$session_count" "$name")\n"
    else
      buf+="$(printf "\033[2m%d %s\033[0m${notify}" "$session_count" "$name")\n"
    fi
  done < <(tmux list-sessions -F '#{session_name}|#{session_attached}')

  buf+="\n\033[1m${current_session}\033[0m\n"

  while IFS='|' read -r pane_id cmd title active; do
    # Claude Code 入力待ちフラグの確認
    if [ -f "/tmp/claude-waiting-${pane_id}" ]; then
      waiting=1
    else
      waiting=0
    fi

    if [ "$active" = "1" ]; then
      if [ "$waiting" = "1" ]; then
        buf+="$(printf "\033[32;1m▶%s \033[5;33;1m●\033[0m" "$cmd")\n"
      else
        buf+="$(printf "\033[32;1m▶%s\033[0m" "$cmd")\n"
      fi
    else
      if [ "$waiting" = "1" ]; then
        buf+="$(printf " \033[37m%s\033[0m \033[5;33;1m●\033[0m" "$cmd")\n"
      else
        buf+="$(printf " \033[37m%s\033[0m" "$cmd")\n"
      fi
    fi
    # pane_title がコマンド名と異なる場合はステータスとして表示
    if [ -n "$title" ] && [ "$title" != "$cmd" ]; then
      buf+="$(printf "\033[2m %s\033[0m" "$title")\n"
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

    # ペイン幅を取得してログ行を切り詰め
    local pane_width
    pane_width=$(tmux display-message -p '#{pane_width}' 2>/dev/null)
    [ -z "$pane_width" ] && pane_width=30

    # 下部に配置
    local log_start=$((pane_height - log_area))
    buf+="\033[${log_start};1H"
    buf+="\033[2m"
    while IFS= read -r line; do
      buf+="${line:0:$pane_width}\n"
    done < <(tail -"$log_area" "$merged_log")
    buf+="\033[0m"
  fi
  rm -f "$merged_log"

  # カーソルをホームへ移動+画面消去してからバッファを一括出力（ちらつき軽減）
  printf '\033[H\033[2J'"$buf"
}

# SIGUSR1 でフラグを立てて再描画をトリガー
# bash 3.2 では read -n がシグナルで中断されないため、read -t 1 ポーリングで検知
needs_render=0
trap 'needs_render=1' USR1

while true; do
  render
  needs_render=0
  while [ "$needs_render" = "0" ]; do
    if read -t 1 -n 1 key 2>/dev/null; then
      if [[ "$key" =~ ^[0-9]$ ]] && [ "$key" -ge 1 ] && [ "$key" -le "$session_count" ]; then
        target=$(tmux list-sessions -F '#{session_name}' | sed -n "${key}p")
        [ -n "$target" ] && tmux switch-client -t "$target"
      fi
      # 入力バッファに残ったエスケープシーケンスを捨てる
      read -t 1 -n 100 _discard 2>/dev/null
      break
    fi
  done
done
