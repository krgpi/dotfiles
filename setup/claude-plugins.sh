#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v claude &>/dev/null; then
    echo "claude not found, skipping Claude Code plugin setup"
    exit 0
fi

if claude plugin marketplace list | grep -q "karaage-dotfiles"; then
    echo "Claude Code marketplace karaage-dotfiles is already added"
    exit 0
fi

echo "Adding Claude Code marketplace"
claude plugin marketplace add "$DOTFILES_DIR/claude-marketplace"
