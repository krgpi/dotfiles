#!/bin/bash

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

echo "Setting up dotfiles from $DOTFILES_DIR (OS: $OS)"

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
create_symlink "$DOTFILES_DIR/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
create_symlink "$DOTFILES_DIR/claude/skills/commit-edited" "$HOME/.claude/skills/commit-edited"
create_symlink "$DOTFILES_DIR/claude/skills/fix-gh-ci-error" "$HOME/.claude/skills/fix-gh-ci-error"
create_symlink "$DOTFILES_DIR/.tmux.conf" "$HOME/.tmux.conf"
create_symlink "$DOTFILES_DIR/mise_config.toml" "$HOME/.config/mise/config.toml"

if [[ "$OS" == "Darwin" ]]; then
    create_symlink "$DOTFILES_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
    create_symlink "$DOTFILES_DIR/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json"
    create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$HOME/Library/Application Support/lazygit/config.yml"
else
    create_symlink "$DOTFILES_DIR/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
    create_symlink "$DOTFILES_DIR/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"
fi

echo ""
echo "Done! Dotfiles setup complete."

if [[ "$OS" == "Linux" ]]; then
    echo ""
    echo "=== Ubuntu Package Setup ==="
    echo "以下のコマンドでパッケージをインストールできます:"
    echo "  sudo apt update && xargs -a $DOTFILES_DIR/Aptfile sudo apt install -y"
fi

echo ""
echo "=== Claude Code Plugin Setup ==="
echo "Claude Code を起動して以下を実行してください:"
echo "  /plugin add $DOTFILES_DIR/claude-marketplace"
echo "auto-update を有効にすると、変更が自動で同期されます。"
