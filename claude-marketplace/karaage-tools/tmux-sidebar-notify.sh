#!/opt/homebrew/bin/bash
# tmux サイドバー通知管理
# Claude Code のフックから呼び出す
#
# アクション:
#   set-waiting-silent   待機フラグON（ログなし）。既読ロック中はスキップ
#   set-waiting-log      待機フラグON + stdinのmessageをログに記録。既読ロック中はスキップ
#   clear-waiting-silent 待機フラグOFF + 既読ロックON（再通知を抑制）
#   clear-waiting-log    待機フラグOFF + 既読ロックON + ラベルをログに記録
#   reset-lock           待機フラグ・既読ロックの両方をクリア + 実行中フラグON（UserPromptSubmit用）
#   set-running          実行中フラグON（PostToolUse用。承認待ちで止まったあとの再開を拾う）
#   clear-running        実行中フラグOFF（Stop用）
#
# 実行中フラグ /tmp/claude-running-{PANE_ID} はピッカー（tmux-picker.sh）が
# 「Claude が今動いている」を点滅で出すために見る。人待ち（set-waiting）でも消す。
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
READ_LOCK="/tmp/claude-read-${PANE_ID}"
RUNNING_FILE="/tmp/claude-running-${PANE_ID}"
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

case "$ACTION" in
  set-waiting-silent)
    # 人待ちなので実行中ではない。既読ロック中でも消す（Esc で中断したあとの取りこぼし対策）
    rm -f "$RUNNING_FILE"
    # 既読ロックがあれば再通知しない（idle_promptの再発火対策）
    [ -f "$READ_LOCK" ] && exit 0
    touch "$FLAG_FILE"
    ;;
  set-waiting-log)
    rm -f "$RUNNING_FILE"
    [ -f "$READ_LOCK" ] && exit 0
    touch "$FLAG_FILE"
    msg=$(extract_message)
    log_event "${msg:-$LABEL}"
    ;;
  clear-waiting-silent)
    # 既読にしたことを記録し、次のプロンプト送信までset-waitingを抑制
    rm -f "$FLAG_FILE" "$RUNNING_FILE"
    touch "$READ_LOCK"
    ;;
  clear-waiting-log)
    rm -f "$FLAG_FILE" "$RUNNING_FILE"
    touch "$READ_LOCK"
    log_event "$LABEL"
    ;;
  reset-lock)
    # プロンプト送信時: 既読ロックとフラグの両方をクリア（次の完了で再通知可能にする）
    rm -f "$FLAG_FILE" "$READ_LOCK"
    touch "$RUNNING_FILE"
    ;;
  set-running)
    # ステータスバーには実行中を出さないので再描画しない（ツール呼び出しごとに走るため）
    touch "$RUNNING_FILE"
    exit 0
    ;;
  clear-running)
    rm -f "$RUNNING_FILE"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac

# ステータスバーを即時更新
tmux refresh-client -S 2>/dev/null || true
