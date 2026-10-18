#!/bin/bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s)"

echo "Creating symlinks from $DOTFILES_DIR (OS: $OS)"

create_symlink() {
    local source="$1"
    local target="$2"

    if [ -e "$target" ] || [ -L "$target" ]; then
        if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
            echo "$target is already linked"
            return
        fi

        echo "Backing up existing $target to ${target}.backup"
        mv "$target" "${target}.backup"
    fi

    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
    echo "Created symlink: $target -> $source"
}

create_symlink "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
create_symlink "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
create_symlink "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
create_symlink "$DOTFILES_DIR/claude-work/settings.json" "$HOME/.claude-work/settings.json"
create_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.claude/AGENTS.md"
create_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.claude-work/AGENTS.md"
create_symlink "$DOTFILES_DIR/agents/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
create_symlink "$DOTFILES_DIR/agents/CLAUDE.md" "$HOME/.claude-work/CLAUDE.md"
create_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
create_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.codex-work/AGENTS.md"
create_symlink "$DOTFILES_DIR/claude/skills/commit-edited" "$HOME/.claude/skills/commit-edited"
create_symlink "$DOTFILES_DIR/claude/skills/fix-gh-ci-error" "$HOME/.claude/skills/fix-gh-ci-error"
create_symlink "$DOTFILES_DIR/claude/skills/commit-edited" "$HOME/.claude-work/skills/commit-edited"
create_symlink "$DOTFILES_DIR/claude/skills/fix-gh-ci-error" "$HOME/.claude-work/skills/fix-gh-ci-error"
create_symlink "$DOTFILES_DIR/mise_config.toml" "$HOME/.config/mise/config.toml"
create_symlink "$DOTFILES_DIR/hooks/pre-commit" "$DOTFILES_DIR/.git/hooks/pre-commit"
create_symlink "$DOTFILES_DIR/hooks/commit-msg" "$DOTFILES_DIR/.git/hooks/commit-msg"

if [[ "$OS" == "Darwin" ]]; then
    create_symlink "$DOTFILES_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
    create_symlink "$DOTFILES_DIR/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"
    create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$HOME/Library/Application Support/lazygit/config.yml"
else
    create_symlink "$DOTFILES_DIR/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
    create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"
fi
