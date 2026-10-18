#!/bin/bash
set -euo pipefail

clone_if_missing() {
    local repo="$1"
    local dest="$2"

    if [ -d "$dest" ]; then
        echo "$dest already exists"
        return
    fi

    git clone "$repo" "$dest"
}

clone_if_missing https://github.com/romkatv/zsh-defer.git "$HOME/Developer/zsh-defer"
clone_if_missing https://github.com/Aloxaf/fzf-tab.git "$HOME/Developer/fzf-tab"
