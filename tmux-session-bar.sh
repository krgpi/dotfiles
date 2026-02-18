#!/bin/bash

# tmux ステータスバー用セッション一覧生成
# status-left から #() で呼び出される
# tmux のフォーマット文字列を出力する

current_session=$(tmux display-message -p '#S' 2>/dev/null) || exit 0

buf=""
count=0
pos=0  # 表示上の文字位置（クリック判定用）
positions=""  # セッション名|開始位置|終了位置 のリスト

while IFS='|' read -r name attached; do
  ((count++))

  # セッション内のClaude Codeインジケーター（○=動作中/既読、●=未読）
  indicator=""
  indicator_width=0
  while IFS='|' read -r pane_id cmd; do
    [ "$cmd" = "claude" ] || continue
    if [ -f "/tmp/claude-waiting-${pane_id}" ]; then
      indicator+="#[fg=yellow,bold]●#[default]"
    else
      indicator+="○"
    fi
    ((indicator_width++))
  done < <(tmux list-panes -t "$name" -F '#{pane_id}|#{pane_current_command}' 2>/dev/null)

  # インジケーターがあればスペースを挟む
  if [ -n "$indicator" ]; then
    indicator=" ${indicator}"
    ((indicator_width++))  # スペース分
  fi

  # 表示幅を計算: " {count} {name}{indicator} " + 区切りスペース
  # フォーマット: " 1 session_name○ " （前後スペース含む）
  text_width=$(( 1 + ${#count} + 1 + ${#name} + indicator_width + 1 ))

  start_pos=$pos

  if [ "$name" = "$current_session" ]; then
    # indicator内の色指定にも背景色を維持
    active_indicator="${indicator//#\[default\]/#[bg=colour238]}"
    active_indicator="${active_indicator//#\[fg=yellow,bold\]/#[bg=colour238,fg=yellow,bold]}"
    buf+="#[bg=colour238,fg=cyan,bold] ${count} ${name}${active_indicator} #[default] "
    pos=$(( pos + text_width + 1 ))  # 後続の区切りスペース
  elif [ "$attached" -ge 1 ] 2>/dev/null; then
    buf+="#[fg=white] ${count} ${name}#[default]${indicator} "
    pos=$(( pos + text_width ))
  else
    buf+="#[fg=colour245] ${count} ${name}#[default]${indicator} "
    pos=$(( pos + text_width ))
  fi

  positions+="${name}|${start_pos}|${pos}"$'\n'
done < <(tmux list-sessions -F '#{session_name}|#{session_attached}')

# クリック判定用の位置情報を書き出す
printf '%s' "$positions" > /tmp/tmux-session-positions

printf '%s' "$buf"
