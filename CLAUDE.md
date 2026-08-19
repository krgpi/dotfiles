# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

macOS / Ubuntu 両対応の dotfiles リポジトリ。シンボリックリンクベースで設定ファイルを管理する。OS判定（`uname -s`）で macOS 固有の設定（Karabiner, pbcopy, iTerm2 等）を分岐する。

## よく使うコマンド

```bash
# シンボリックリンクの作成・更新
./setup.sh

# macOS: Homebrewパッケージの一括インストール
brew bundle --file=~/Developer/dotfiles/Brewfile

# macOS: Brewfileの更新（現在インストール済みのものをダンプ）
brew bundle dump --file=~/Developer/dotfiles/Brewfile --force

# Ubuntu: aptパッケージの一括インストール
sudo apt update && xargs -a ~/Developer/dotfiles/Aptfile sudo apt install -y
```

## アーキテクチャ

### デプロイ方式

`setup.sh` がすべての設定ファイルをホームディレクトリ等へシンボリックリンクする。既存ファイルは `.backup` 付きでバックアップされる。


### 主要コンポーネント

- **zsh** (`.zshrc`): zsh-deferによる遅延読み込みでパフォーマンス最適化。compinit は1日1回のみ実行。環境変数は `.env` から読み込み（gitignore対象）
- **Neovim** (`nvim/`): lazy.nvim でプラグイン管理。エントリポイントは `nvim/init.lua`、設定は `nvim/lua/options/`、プラグインは `nvim/lua/plugins/`
- **Claude Code** (`claude/`): グローバル設定・カスタムコマンド（ask-gemini, mk-pr, x-search）・hooks（tmux未読通知, Prettier自動整形, ccusage）
- **自動更新** (`dotfiles-update.sh`): 1日1回、ターミナル起動時に zsh-defer 経由でバックグラウンド実行。`brew update` + `brew upgrade --formula` と fzf-tab / zsh-defer の `git pull` を行う。cask は起動中アプリの差し替えを避けるため件数通知のみ。結果は次回のターミナル起動時に一度だけ表示される。`up` で即時実行でき、その場に結果を出力する。実行履歴（更新されたコミット一覧を含む）は `~/.cache/dotfiles-update/last.log` に追記される（直近500行を保持）
- **tmux** (`.tmux.conf`): vim風キーバインド。`tmux-dev-layout.sh` で3ペイン開発環境を自動構築（エディタ + lazygit + claude）

### tmux × Claude Code 並列運用

複数プロジェクトでClaude Codeを同時並行で動かし、人間の注意を最適配分するための仕組み。設計思想は「待っている → 気づく → 切り替える → 対応する」のループを最小認知負荷で回すこと。

- **未読/既読インジケーター**: ステータスバーでどのセッションのClaudeが入力待ちかを一目で識別できる
- **既読ロック**: 確認済みのセッションが再通知で光り直す問題を防止する仕組み
- **高速セッション切り替え**: 数字キー・マウスクリックでセッション間を即座に移動

### セキュリティ

- `.env` ファイルはgitignore対象。APIキーやトークンはすべて `.env` で管理
- `hooks/pre-commit` が `.sensitive-words` に定義された機密ワードのコミットをブロックする

### 規約

- ドキュメント・コメントは日本語で記述する
- macOS: Homebrew の追加・削除は `Brewfile` を直接編集したあとに、homebrewのコマンドを実行する
- Ubuntu: apt パッケージの追加・削除は `Aptfile` を直接編集する
- 新しい設定ファイルを追加する場合は `setup.sh` にシンボリックリンクの定義も追加する
