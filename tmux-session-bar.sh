#!/bin/bash

# tmux ステータスバー用セッション一覧生成
# status-left から #() で呼び出される
# tmux のフォーマット文字列を出力する

current_session=$(tmux display-message -p '#S' 2>/dev/null) || exit 0

buf=""
count=0

while IFS='|' read -r name attached; do
  ((count++))

  # セッション内のClaude Codeインジケーター（○=動作中/既読、●=未読）
  indicator=""
  while IFS='|' read -r pane_id cmd; do
    [ "$cmd" = "claude" ] || continue
    if [ -f "/tmp/claude-waiting-${pane_id}" ]; then
      indicator+="#[blink,fg=yellow,bold]●#[noblink,default]"
    else
      indicator+="○"
    fi
  done < <(tmux list-panes -t "$name" -F '#{pane_id}|#{pane_current_command}' 2>/dev/null)

  # インジケーターがあればスペースを挟む
  [ -n "$indicator" ] && indicator=" ${indicator}"

  if [ "$name" = "$current_session" ]; then
    buf+="#[fg=cyan,bold] ${count} ▶${name}#[default]${indicator} "
  elif [ "$attached" -ge 1 ] 2>/dev/null; then
    buf+="#[fg=white] ${count} ${name}#[default]${indicator} "
  else
    buf+="#[fg=colour245] ${count} ${name}#[default]${indicator} "
  fi
done < <(tmux list-sessions -F '#{session_name}|#{session_attached}')

printf '%s' "$buf"
