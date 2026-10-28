#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v mise &>/dev/null; then
    echo "mise not found, skipping npm global packages"
    exit 0
fi

echo "Installing mise tools"
mise install
mise install node@24

echo "Installing npm global packages"
xargs "$(mise where node@24)/bin/npm" install --ignore-scripts -g < "$DOTFILES_DIR/Npmfile"
