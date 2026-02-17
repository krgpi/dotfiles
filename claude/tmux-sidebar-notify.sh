#!/bin/bash
# tmux サイドバー通知管理
# Claude Code のフックから呼び出す
#
# アクション:
#   set-waiting-silent   待機フラグON（ログなし）
#   set-waiting-log      待機フラグON + stdinのmessageをログに記録
#   clear-waiting-silent 待機フラグOFF（ログなし）
#   clear-waiting-log    待機フラグOFF + ラベルをログに記録
#
# ログは /tmp/claude-sidebar-log-{PANE_ID} に追記され、サイドバー左下に表示される

# stdinからJSONを読み取る（タイムアウト付き）
STDIN_JSON=""
if read -t 1 -r STDIN_JSON; then
  while read -t 0.1 -r line; do
    STDIN_JSON+="$line"
  done
fi

ACTION="${1:-}"
LABEL="${2:-}"
PANE_ID="${TMUX_PANE:-}"

# TMUX_PANE が未設定なら tmux 外なのでスキップ
[ -z "$PANE_ID" ] && exit 0

FLAG_FILE="/tmp/claude-waiting-${PANE_ID}"
LOG_FILE="/tmp/claude-sidebar-log-${PANE_ID}"

# stdinのJSONからmessageを抽出
extract_message() {
  if [ -n "$STDIN_JSON" ] && command -v jq &>/dev/null; then
    jq -r '.message // empty' <<< "$STDIN_JSON" 2>/dev/null
  fi
}

# ログ追記（タイムスタンプ + テキスト）
log_event() {
  local text="$1"
  [ -z "$text" ] && return
  local ts
  ts=$(date '+%H:%M:%S')
  echo "${ts} ${text}" >> "$LOG_FILE"
  # ログファイルが大きくなりすぎないよう最新50行に制限
  local lines
  lines=$(wc -l < "$LOG_FILE" 2>/dev/null)
  lines=${lines// /}
  if [ "$lines" -gt 50 ] 2>/dev/null; then
    tail -20 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

# このペインが現在アクティブ（フォーカス中）かどうかを判定
is_pane_active() {
  local active
  active=$(tmux display-message -t "$PANE_ID" -p '#{pane_active}' 2>/dev/null)
  [ "$active" = "1" ]
}

case "$ACTION" in
  set-waiting-silent)
    # フォーカス中のペインなら通知不要（見ているので既読扱い）
    is_pane_active && exit 0
    touch "$FLAG_FILE"
    ;;
  set-waiting-log)
    touch "$FLAG_FILE"
    msg=$(extract_message)
    log_event "${msg:-$LABEL}"
    ;;
  clear-waiting-silent)
    rm -f "$FLAG_FILE"
    ;;
  clear-waiting-log)
    rm -f "$FLAG_FILE"
    log_event "$LABEL"
    ;;
  *)
    exit 1
    ;;
esac

# サイドバープロセスに SIGUSR1 を送って即時再描画
pkill -USR1 -f "[t]mux-session-sidebar" 2>/dev/null || true
