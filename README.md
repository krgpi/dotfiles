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

### 7. 環境変数の設定

以下の環境変数を `.env` ファイルを作って設定する:

| 変数名           | 用途                                           | 取得先                                           |
| ---------------- | ---------------------------------------------- | ------------------------------------------------ |
| `XAI_API_KEY`    | Claude Code の `/x-search` コマンド (Grok API) | [xAI Console](https://console.x.ai/)             |
| `X_BEARER_TOKEN` | Claude Code の `/x-search` コマンド (X API v2) | [X Developer Portal](https://developer.x.com/)   |
