#!/bin/bash

# セッション名（お好みで変更してください）
SESSION="dev"

# 作業ディレクトリ（スクリプト実行時のカレントディレクトリ）
WORK_DIR="$(pwd)"

# すでにセッションがある場合はアタッチだけして終了
tmux has-session -t $SESSION 2>/dev/null
if [ $? -eq 0 ]; then
    tmux attach-session -t $SESSION
    exit 0
fi

# 1. 新規セッションをデタッチ状態で開始（左上：自由エリア）
tmux new-session -d -s $SESSION -c "$WORK_DIR"

# マウスサポートを有効化
tmux set-option -t $SESSION -g mouse on

# 2. 右側にClaude Code用ペインを作成
tmux split-window -h -p 30 -t $SESSION -c "$WORK_DIR"

# 3. 左側のペイン(0)を上下に分割
tmux select-pane -t dev.0
tmux split-window -v -p 80 -t $SESSION -c "$WORK_DIR"

# シェルの初期化を待つ
sleep 0.5

# 4. コマンド起動
# 右ペイン（Claude Code）
tmux send-keys -t dev.2 'claude' C-m
# 左下ペイン（lazygit）
tmux send-keys -t dev.1 'lazygit' C-m

# 5. 最後にフォーカスを左上の「自由エリア」に戻す
# tmux select-pane -t dev.0

# セッションにアタッチ
tmux attach-session -t $SESSION
