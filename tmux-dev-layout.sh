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
    tmux send-keys -t "$claude_pane" 'claude' C-m

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

    # 最初のセッションにアタッチ
    tmux attach-session 2>/dev/null
    exit 0
fi

# 通常のセッション作成
if [ -n "$1" ]; then
    WORK_DIR="$(cd "$1" 2>/dev/null && pwd)" || { echo "エラー: ディレクトリが見つかりません: $1" >&2; exit 1; }
else
    WORK_DIR="$(pwd)"
fi

if tmux has-session -t "$(basename "$WORK_DIR")" 2>/dev/null; then
    echo "セッション '$(basename "$WORK_DIR")' は既に存在します"
    tmux refresh-client -S 2>/dev/null || true
    # tmux外からの場合はアタッチ
    if [ -z "$TMUX" ]; then
        tmux attach-session -t "$(basename "$WORK_DIR")"
    fi
    exit 0
fi

create_session "$WORK_DIR"

# tmuxの外から実行された場合はセッションにアタッチする
if [ -z "$TMUX" ]; then
    tmux attach-session -t "$(basename "$WORK_DIR")"
fi
