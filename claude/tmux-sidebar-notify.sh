#!/bin/bash
# tmux サイドバー通知フラグ管理
# Claude Code のフック（idle_prompt/permission_prompt/UserPromptSubmit等）から呼び出す
#
# 使い方:
#   tmux-sidebar-notify.sh set-waiting    # 待機フラグを立てる
#   tmux-sidebar-notify.sh clear-waiting  # 待機フラグを消す

# stdin を捨てる（Claude Code は常に JSON を stdin に送るため）
cat > /dev/null &

ACTION="${1:-}"
PANE_ID="${TMUX_PANE:-}"

# TMUX_PANE が未設定なら tmux 外なのでスキップ
[ -z "$PANE_ID" ] && exit 0

FLAG_FILE="/tmp/claude-waiting-${PANE_ID}"

case "$ACTION" in
  set-waiting)
    touch "$FLAG_FILE"
    ;;
  clear-waiting)
    rm -f "$FLAG_FILE"
    ;;
  *)
    exit 1
    ;;
esac

# サイドバープロセスに SIGUSR1 を送って即時再描画
pkill -USR1 -f "[t]mux-session-sidebar" 2>/dev/null || true
