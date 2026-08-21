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

## 開発環境（dev コマンド）

`dev` は tmux 上に「フォルダ → セッション」の2階層で開発環境を組み立てる。左端には全フォルダ・全セッションを一覧するサイドバーが常駐する。

```sh
dev ~/Developer/myapp   # フォルダを開く（claude1 / lg / nv が立ち上がる）
dev                     # 直近に使っていたフォルダへ戻る
dev restart             # 全フォルダを同じ構成で作り直す
```

| キー | 動作 |
| --- | --- |
| `prefix 1`〜`9` | フォルダ切り替え（続けて数字でその中のセッションへ） |
| `prefix h` / `l` | セッションを前後に移動 |
| `prefix c` / `t` / `g` / `e` | セッション追加（claude / シェル / lazygit / エディタ） |
| `prefix o` | フォルダを追加（fzf-tab のディレクトリ補完。Tab で階層を辿り、Enter で開く） |
| `prefix x` / `X` | セッションを閉じる / フォルダごと閉じる |
| `prefix b` | サイドバーの表示切替 |

環境変数で挙動を変えられる。

| 変数名 | 既定値 | 用途 |
| --- | --- | --- |
| `TMUX_DEV_ROOTS` | `~/Developer` | `prefix o` で候補にするディレクトリ（`:` 区切りで複数指定可） |
| `TMUX_DEV_CLAUDE_CMD` | `claude` | `claudeN` セッションで起動するコマンド |
| `TMUX_DEV_EDITOR_CMD` | `nvim .` | `nv` セッションで起動するコマンド |
| `TMUX_SIDEBAR_WIDTH` | `28` | サイドバーの幅（カラム数） |
