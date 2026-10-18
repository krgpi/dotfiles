# dotfiles

## セットアップ

### 1. リポジトリのクローンと setup.sh の実行

```sh
git clone https://github.com/<your-username>/dotfiles.git ~/Developer/dotfiles
~/Developer/dotfiles/setup.sh
```

`setup.sh` は `setup/` 配下のスクリプトを順に実行する。どれも何度実行しても同じ結果になる。

| スクリプト                 | 内容                                                                 |
| -------------------------- | -------------------------------------------------------------------- |
| `setup/packages.sh`        | macOS: Homebrew のインストールと `brew bundle`。Ubuntu: `Aptfile` の apt install |
| `setup/zsh-plugins.sh`     | zsh-defer・fzf-tab を `~/Developer` にクローン                       |
| `setup/symlinks.sh`        | 設定ファイルのシンボリックリンク作成                                 |
| `setup/npm.sh`             | `mise install` と `Npmfile` の npm グローバルインストール            |
| `setup/claude-plugins.sh`  | Claude Code に `claude-marketplace` を追加                          |
| `setup/env.sh`             | `.env` が無ければ空のテンプレートを作成                              |
| `setup/macos.sh`           | macOS の `defaults` を一括適用（macOS のみ）                         |

個別に流したいときは各スクリプトを直接実行すればいい。

### 2. 環境変数の設定

`setup/env.sh` が作った `.env` に以下の値を埋める:

| 変数名           | 用途                                           | 取得先                                           |
| ---------------- | ---------------------------------------------- | ------------------------------------------------ |
| `XAI_API_KEY`    | Claude Code の `/x-search` コマンド (Grok API) | [xAI Console](https://console.x.ai/)             |
| `X_BEARER_TOKEN` | Claude Code の `/x-search` コマンド (X API v2) | [X Developer Portal](https://developer.x.com/)   |

### 3. 再ログイン（macOS のみ）

`setup/macos.sh` で適用した `defaults` の一部は再ログイン後に反映される。

## Codex

`codex` と `codex-work` は別々の `CODEX_HOME` を使う。通常用は `~/Developer/dotfiles/codex`、仕事用は `~/Developer/dotfiles/codex-work` に設定・認証・履歴を分ける。

```sh
codex login
codex-work login
```

`config.toml` と `AGENTS.md` はこのリポジトリで管理する。`auth.json`、履歴、DB、キャッシュなどのローカルデータは gitignore 対象。

カスタムスキルは `codex/skills/<name>/` に直接置けばリポジトリで管理される（`skills/.system/` はCodexが自動生成するシステムスキルなので除外）。
