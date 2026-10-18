# dotfiles

## セットアップ

### 1. Homebrew のインストール

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. リポジトリのクローン

```sh
git clone https://github.com/<your-username>/dotfiles.git ~/Developer/dotfiles
```

### 3. Brewfile でパッケージをインストール

```sh
brew bundle --file=~/Developer/dotfiles/Brewfile
```

### 4. zsh-defer のインストール

```sh
git clone https://github.com/romkatv/zsh-defer.git ~/Developer/zsh-defer
```

### 5. fzf-tab のインストール

```sh
git clone https://github.com/Aloxaf/fzf-tab.git ~/Developer/fzf-tab
```

### 6. シンボリックリンクの作成

```sh
~/Developer/dotfiles/setup.sh
```

### 7. Claude Code プラグインの追加

```sh
cd ~/Developer/dotfiles
claude /plugin marketplace add ./claude-marketplace
```

### 8. 環境変数の設定

以下の環境変数を `.env` ファイルを作って設定する:

| 変数名           | 用途                                           | 取得先                                           |
| ---------------- | ---------------------------------------------- | ------------------------------------------------ |
| `XAI_API_KEY`    | Claude Code の `/x-search` コマンド (Grok API) | [xAI Console](https://console.x.ai/)             |
| `X_BEARER_TOKEN` | Claude Code の `/x-search` コマンド (X API v2) | [X Developer Portal](https://developer.x.com/)   |

### 9. macOS のシステム設定（macOS のみ）

```sh
~/Developer/dotfiles/macos.sh
```

Dock・Finder・トラックパッド・スクリーンショットなどの `defaults` を一括で適用する。何度実行しても同じ結果になる。一部の設定は再ログイン後に反映される。

## Codex

`codex` と `codex-work` は別々の `CODEX_HOME` を使う。通常用は `~/Developer/dotfiles/codex`、仕事用は `~/Developer/dotfiles/codex-work` に設定・認証・履歴を分ける。

```sh
codex login
codex-work login
```

`config.toml` と `AGENTS.md` はこのリポジトリで管理する。`auth.json`、履歴、DB、キャッシュなどのローカルデータは gitignore 対象。

カスタムスキルは `codex/skills/<name>/` に直接置けばリポジトリで管理される（`skills/.system/` はCodexが自動生成するシステムスキルなので除外）。
