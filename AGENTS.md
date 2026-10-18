# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and Codex when working with code in this repository.

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

# npmグローバルパッケージの一括インストール（mise管理のnodeに入れる。PATH順に依存しないようフルパス指定）
cat ~/Developer/dotfiles/Npmfile | xargs $(mise where node@24)/bin/npm install --ignore-scripts -g
```

## アーキテクチャ

### デプロイ方式

`setup.sh` がすべての設定ファイルをホームディレクトリ等へシンボリックリンクする。既存ファイルは `.backup` 付きでバックアップされる。


### 主要コンポーネント

- **zsh** (`.zshrc`): zsh-deferによる遅延読み込みでパフォーマンス最適化。compinit は1日1回のみ実行。環境変数は `.env` から読み込み（gitignore対象）
- **Neovim** (`nvim/`): lazy.nvim でプラグイン管理。エントリポイントは `nvim/init.lua`、設定は `nvim/lua/options/`、プラグインは `nvim/lua/plugins/`。telescope と mason は起動時に読まず、キーマップ（`keys`）とバッファを開いたとき（`event`）まで遅らせている
- **macOS のシステム設定** (`macos.sh`): Dock・Finder・トラックパッド・スクリーンショット・メニューバーなどの `defaults` を一括適用する。`setup.sh` からは実行せず手動で叩く。ウィンドウ位置やマシン固有の識別子など環境依存の値は持たない
- **自動更新** (`dotfiles-update.sh`): 1日1回、ターミナル起動時に zsh-defer 経由でバックグラウンド実行。`brew update` + `brew upgrade --formula` と fzf-tab / zsh-defer の `git pull` を行う。cask は起動中アプリの差し替えを避けるため件数通知のみ。結果は次回のターミナル起動時に一度だけ表示される。`up` で即時実行でき、その場に結果を出力する。実行履歴（更新されたコミット一覧を含む）は `~/.cache/dotfiles-update/last.log` に追記される（直近500行を保持）

### セキュリティ

- `.env` ファイルはgitignore対象。APIキーやトークンはすべて `.env` で管理
- `hooks/pre-commit` が `.sensitive-words` に定義された機密ワードのコミットをブロックする

### 規約

- ドキュメント・コメントは日本語で記述する
- macOS: Homebrew の追加・削除は `Brewfile` を直接編集したあとに、homebrewのコマンドを実行する
- Ubuntu: apt パッケージの追加・削除は `Aptfile` を直接編集する
- 新しい設定ファイルを追加する場合は `setup.sh` にシンボリックリンクの定義も追加する
