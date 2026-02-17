#!/bin/bash

# tmux セッション/ペイン一覧サイドバー
# hookからのSIGUSR1で即座に再描画。
# 数字キーでセッション切り替え可能。

# ペインタイトルを固定（pane-title-changed hookの無限ループ防止）
printf '\033]2;sidebar\033\\'
# マウスレポーティングを無効化（マウスのエスケープシーケンスがstdinに流れ込むのを防ぐ）
printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l'

session_count=0

# セッション内のClaude Codeペインの状態インジケーターを生成
# 既読/動作中=○、未読(回答完了/許可待ち)=●（点滅黄色）
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
    # Claude Code 未読通知フラグの確認
    if [ -f "/tmp/claude-waiting-${pane_id}" ]; then
      waiting=1
    else
      waiting=0
    fi

    if [ "$active" = "1" ]; then
      if [ "$waiting" = "1" ]; then
        buf+="$(printf "\033[36;1m▶%s \033[5;33;1m●\033[0m" "$cmd")\n"
      else
        buf+="$(printf "\033[36;1m▶%s\033[0m" "$cmd")\n"
      fi
    else
      if [ "$waiting" = "1" ]; then
        buf+="$(printf "\033[2m %s \033[0;5;33;1m●\033[0m" "$cmd")\n"
      else
        buf+="$(printf "\033[2m %s\033[0m" "$cmd")\n"
      fi
    fi
    # pane_title がコマンド名と異なる場合はステータスとして表示（イタリック+薄色で区別）
    if [ -n "$title" ] && [ "$title" != "$cmd" ]; then
      buf+="$(printf "\033[2;3m  %s\033[0m" "$title")\n"
    fi
  done < <(tmux list-panes -t "$current_session" -F '#{pane_id}|#{pane_current_command}|#{pane_title}|#{pane_active}')

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
