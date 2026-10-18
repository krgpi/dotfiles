#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$DOTFILES_DIR/setup"
OS="$(uname -s)"

run_step() {
    echo ""
    echo "=== $1 ==="
    bash "$SETUP_DIR/$1"
}

run_step packages.sh
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
run_step zsh-plugins.sh
run_step symlinks.sh
run_step npm.sh
run_step claude-plugins.sh
run_step env.sh
[[ "$OS" == "Darwin" ]] && run_step macos.sh

echo ""
echo "Done! Dotfiles setup complete."
