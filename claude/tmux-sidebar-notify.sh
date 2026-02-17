#!/bin/bash
# tmux サイドバー通知管理
# Claude Code のフック（idle_prompt/permission_prompt/UserPromptSubmit等）から呼び出す
#
# 使い方:
#   tmux-sidebar-notify.sh set-waiting    # 待機フラグ + ログ追記
#   tmux-sidebar-notify.sh clear-waiting  # 待機フラグ解除 + ログ追記
#
# ログは /tmp/claude-sidebar-log-{PANE_ID} に追記され、サイドバー左下に表示される

# stdin を捨てる（Claude Code は常に JSON を stdin に送るため）
cat > /dev/null &

ACTION="${1:-}"
PANE_ID="${TMUX_PANE:-}"

# TMUX_PANE が未設定なら tmux 外なのでスキップ
[ -z "$PANE_ID" ] && exit 0

FLAG_FILE="/tmp/claude-waiting-${PANE_ID}"
LOG_FILE="/tmp/claude-sidebar-log-${PANE_ID}"

# ログ追記（タイムスタンプ + イベント名）
log_event() {
  local label="$1"
  local ts
  ts=$(date '+%H:%M')
  echo "${ts} ${label}" >> "$LOG_FILE"
  # ログファイルが大きくなりすぎないよう最新50行に制限
  if [ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -gt 50 ]; then
    tail -20 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
  fi
}

LABEL="${2:-}"

case "$ACTION" in
  set-waiting)
    touch "$FLAG_FILE"
    log_event "${LABEL:-Waiting}"
    ;;
  clear-waiting)
    rm -f "$FLAG_FILE"
    log_event "${LABEL:-Working}"
    ;;
  *)
    exit 1
    ;;
esac

# サイドバープロセスに SIGUSR1 を送って即時再描画
pkill -USR1 -f "[t]mux-session-sidebar" 2>/dev/null || true
