#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="$HOME/.local/bin:$PATH"

if ! command -v claude &>/dev/null; then
    echo "Installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash
fi

if claude plugin marketplace list | grep -q "karaage-dotfiles"; then
    echo "Claude Code marketplace karaage-dotfiles is already added"
    exit 0
fi

echo "Adding Claude Code marketplace"
claude plugin marketplace add "$DOTFILES_DIR/claude-marketplace"
