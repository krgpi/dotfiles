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

# このペインをユーザーが実際に見ているかどうかを判定
# pane_active だけでは不十分：別セッションを表示中でもペインはセッション内で active=1 になる
# そのため、ペインが属するセッションが現在クライアントに表示されているかも確認する
is_pane_visible() {
  local pane_session current_session
  # ペインが属するセッション名
  pane_session=$(tmux display-message -t "$PANE_ID" -p '#{session_name}' 2>/dev/null) || return 1
  # 現在クライアントが表示しているセッション名
  current_session=$(tmux display-message -p '#{client_session}' 2>/dev/null) || return 1
  # 同じセッション かつ ペインがアクティブ
  [ "$pane_session" = "$current_session" ] && \
    [ "$(tmux display-message -t "$PANE_ID" -p '#{pane_active}' 2>/dev/null)" = "1" ]
}

case "$ACTION" in
  set-waiting-silent)
    # ユーザーが実際に見ているペインなら通知不要（既読扱い）
    is_pane_visible && exit 0
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

# ステータスバーを即時更新
tmux refresh-client -S 2>/dev/null || true
