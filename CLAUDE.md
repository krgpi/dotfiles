# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

macOS開発環境のdotfilesリポジトリ。シンボリックリンクベースで設定ファイルを管理する。

## よく使うコマンド

```bash
# シンボリックリンクの作成・更新
./setup.sh

# Homebrewパッケージの一括インストール
brew bundle --file=~/Developer/dotfiles/Brewfile

# Brewfileの更新（現在インストール済みのものをダンプ）
brew bundle dump --file=~/Developer/dotfiles/Brewfile --force
```

## アーキテクチャ

### デプロイ方式

`setup.sh` がすべての設定ファイルをホームディレクトリ等へシンボリックリンクする。既存ファイルは `.backup` 付きでバックアップされる。


### 主要コンポーネント

- **zsh** (`.zshrc`): zsh-deferによる遅延読み込みでパフォーマンス最適化。compinit は1日1回のみ実行。環境変数は `.env` から読み込み（gitignore対象）
- **Neovim** (`nvim/`): lazy.nvim でプラグイン管理。エントリポイントは `nvim/init.lua`、設定は `nvim/lua/options/`、プラグインは `nvim/lua/plugins/`
- **Claude Code** (`claude/`): グローバル設定・カスタムコマンド（ask-gemini, mk-pr, x-search）・hooks（LINE通知, Prettier自動整形, ccusage）
- **tmux** (`.tmux.conf`): vim風キーバインド。`tmux-dev-layout.sh` で3ペイン開発環境を自動構築（エディタ + lazygit + claude）

### セキュリティ

- `.env` ファイルはgitignore対象。APIキーやトークンはすべて `.env` で管理
- `hooks/pre-commit` が `.sensitive-words` に定義された機密ワードのコミットをブロックする

### 規約

- ドキュメント・コメントは日本語で記述する
- Homebrew の追加・削除は `Brewfile` を直接編集したあとに、homebrewのコマンドを実行する
- 新しい設定ファイルを追加する場合は `setup.sh` にシンボリックリンクの定義も追加する
