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
