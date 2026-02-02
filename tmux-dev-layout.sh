#!/bin/bash

WORK_DIR="$(pwd)"
SESSION="$(basename "$WORK_DIR")"

tmux has-session -t $SESSION 2>/dev/null
if [ $? -eq 0 ]; then
    tmux attach-session -t $SESSION
    exit 0
fi

tmux new-session -d -s $SESSION -c "$WORK_DIR"

tmux split-window -h -p 30 -t $SESSION -c "$WORK_DIR"

tmux select-pane -t $SESSION.0
tmux split-window -v -p 80 -t $SESSION -c "$WORK_DIR"


tmux send-keys -t $SESSION.2 'claude' C-m
tmux send-keys -t $SESSION.1 'lazygit' C-m
tmux attach-session -t $SESSION
