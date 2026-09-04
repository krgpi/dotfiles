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

## 開発環境（dev コマンド）

`dev` は tmux 上に開発環境を組み立てる。全ウィンドウが1つの tmux セッションに入り、「フォルダ」は各ウィンドウが今いるパスで動的にグルーピングされる。一覧は常駐させず、`prefix Space` のピッカー（fzf）で必要なときだけ出す。

```sh
dev ~/Developer/myapp   # フォルダを開く（claude1 / nv / sh1 の3ウィンドウ）
dev                     # 直近に使っていたフォルダへ戻る
dev restart             # tmux 設定を読み直す（作業中のペインはそのまま）
dev restart --full      # tmux ごと落として同じ構成で作り直す
```

| キー | 動作 |
| --- | --- |
| `prefix Space` | フォルダ/ウィンドウのピッカー（`ctrl-x` でそのウィンドウを閉じる） |
| `prefix h` / `l` | 同じパス内でウィンドウを前後に移動 |
| `prefix H` / `L` | フォルダを前後に移動 |
| `prefix c` / `t` / `e` | ウィンドウ追加（claude / シェル / エディタ） |
| `prefix x` / `X` | ウィンドウを閉じる / フォルダごと閉じる |
| `prefix Tab` | ペインを巡回 |

Claude が入力待ちになるとステータスバー右に `● <フォルダ名>` が出る。lazygit と diff は nvim 側（`<leader>lg` / `<leader>dv`）に集約してあるので専用ウィンドウは持たない。nvim からは `<leader>fp` で同じ一覧を telescope で開ける。

環境変数で挙動を変えられる。

| 変数名 | 既定値 | 用途 |
| --- | --- | --- |
| `TMUX_DEV_SESSION` | `dev` | 使用する tmux セッション名 |
| `TMUX_DEV_CLAUDE_CMD` | `claude` | `claudeN` ウィンドウで起動するコマンド |
| `TMUX_DEV_EDITOR_CMD` | `nvim .` | `nv` ウィンドウで起動するコマンド |
