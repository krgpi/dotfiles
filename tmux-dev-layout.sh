#!/bin/bash

# セッション作成（アタッチなし）
create_session() {
    local work_dir="$1"
    local session="$(basename "$work_dir")"

    tmux has-session -t "$session" 2>/dev/null && return 0

    tmux new-session -d -s "$session" -c "$work_dir"

    # メインを右に30%分割 → lazygit用（-d でフォーカスを変えない、-P でペインIDを取得）
    local lazygit_pane
    lazygit_pane=$(tmux split-window -h -d -p 30 -t "$session" -c "$work_dir" -P -F '#{pane_id}')

    # メイン(まだactive)を下に80%分割 → claude用
    local claude_pane
    claude_pane=$(tmux split-window -v -d -p 80 -t "$session" -c "$work_dir" -P -F '#{pane_id}')

    # gitリポジトリの場合のみlazygitを起動
    if git -C "$work_dir" rev-parse --is-inside-work-tree &>/dev/null; then
        tmux send-keys -t "$lazygit_pane" 'lazygit' C-m
    fi
    tmux send-keys -t "$claude_pane" "${TMUX_DEV_CLAUDE_CMD:-claude}" C-m

    tmux refresh-client -S 2>/dev/null || true
    echo "セッション '$session' を作成しました"
}

# サブコマンド: dev restart
if [ "$1" = "restart" ]; then
    # 全セッションのパスを保存
    session_file="/tmp/tmux-dev-sessions"
    tmux list-sessions -F '#{session_path}' 2>/dev/null > "$session_file"
    if [ ! -s "$session_file" ]; then
        echo "エラー: 復元するセッションがありません" >&2
        rm -f "$session_file"
        exit 1
    fi

    echo "復元対象:"
    cat "$session_file"

    # tmux内から実行された場合: detachしてからkill→復元→attach
    # tmux外から実行された場合: そのままkill→復元→attach
    if [ -n "$TMUX" ]; then
        # detachすることで、元のターミナルのshellに制御が戻る
        # そこで復元スクリプトを実行するため、tmux detach後にこのスクリプトを再実行
        SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        tmux detach-client -E "exec '$SELF' restart"
        exit 0
    fi

    # ここはtmux外で実行されている（detach後の再実行 or 最初からtmux外）
    tmux kill-server 2>/dev/null
    sleep 0.5

    # 各セッションを再作成
    while IFS= read -r dir; do
        [ -d "$dir" ] || continue
        echo "復元中: $dir"
        create_session "$dir"
    done < "$session_file"
    rm -f "$session_file"

    # 最初のセッションにリンクセッションでアタッチ
    first_session=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1)
    tmux new-session -t "$first_session" 2>/dev/null
    exit 0
fi

# 引数なし: 新規作成せず、直近にアタッチされた既存セッションへ即アタッチ
if [ -z "$1" ]; then
    if [ -n "$TMUX" ]; then
        current_session="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
    else
        current_session=""
    fi

    # session_last_attached の降順に並べ、現在のセッションを除いた直近を選ぶ
    # 未アタッチのセッションでは session_last_attached が空になるため0として扱う
    target_session="$(tmux list-sessions -F "#{session_last_attached}"$'\t'"#{session_name}" 2>/dev/null \
        | awk -F'\t' -v cur="$current_session" '$2 != cur { printf "%d\t%s\n", $1, $2 }' \
        | sort -rn \
        | head -1 \
        | cut -f2-)"

    if [ -z "$target_session" ]; then
        echo "アタッチできる既存セッションがありません（'dev .' で現在のディレクトリのセッションを作成できます）" >&2
        exit 1
    fi

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$target_session"
    else
        tmux attach-session -t "$target_session"
    fi
    exit 0
fi

# パス指定: セッション作成（既存ならそのまま）
WORK_DIR="$(cd "$1" 2>/dev/null && pwd)" || { echo "エラー: ディレクトリが見つかりません: $1" >&2; exit 1; }

session_name="$(basename "$WORK_DIR")"

if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "セッション '$session_name' は既に存在します"
    tmux refresh-client -S 2>/dev/null || true
else
    create_session "$WORK_DIR"
fi

# 現在のセッションと異なる場合はアタッチ/切り替え
# tmux外では display-message が直近のセッション名を返すため、$TMUX で判定する
if [ -n "$TMUX" ]; then
    current_session="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
    if [ "$current_session" != "$session_name" ]; then
        tmux switch-client -t "$session_name"
    fi
else
    tmux attach-session -t "$session_name"
fi
