#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! command -v brew &>/dev/null && [[ ! -x /opt/homebrew/bin/brew ]]; then
        echo "Installing Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    eval "$(/opt/homebrew/bin/brew shellenv)"

    echo "Installing Homebrew packages"
    brew bundle --file="$DOTFILES_DIR/Brewfile"
else
    echo "Installing apt packages"
    sudo apt update
    xargs -a "$DOTFILES_DIR/Aptfile" sudo apt install -y
fi
