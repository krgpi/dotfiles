#!/bin/bash

# 引数があればそのパスを、なければカレントディレクトリを使用
if [ -n "$1" ]; then
    WORK_DIR="$(cd "$1" 2>/dev/null && pwd)" || { echo "エラー: ディレクトリが見つかりません: $1" >&2; exit 1; }
else
    WORK_DIR="$(pwd)"
fi
SESSION="$(basename "$WORK_DIR")"

tmux has-session -t "$SESSION" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "セッション '$SESSION' は既に存在します"
    exit 0
fi

# セッション作成（after-new-session hookでサイドバーが左端に自動追加される）
tmux new-session -d -s "$SESSION" -c "$WORK_DIR"

# hookにより サイドバー(左10列) + メイン(右) の状態。メインがactive。
# メインを右に30%分割 → lazygit用（-d でフォーカスを変えない、-P でペインIDを取得）
lazygit_pane=$(tmux split-window -h -d -p 30 -t "$SESSION" -c "$WORK_DIR" -P -F '#{pane_id}')

# メイン(まだactive)を下に80%分割 → claude用
claude_pane=$(tmux split-window -v -d -p 80 -t "$SESSION" -c "$WORK_DIR" -P -F '#{pane_id}')

tmux send-keys -t "$lazygit_pane" 'lazygit' C-m
tmux send-keys -t "$claude_pane" 'claude' C-m

# tmuxの外から実行された場合はセッションにアタッチする
if [ -z "$TMUX" ]; then
    tmux attach-session -t "$SESSION"
else
    echo "セッション '$SESSION' を作成しました"
fi
