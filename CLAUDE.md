# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

macOS / Ubuntu 両対応の dotfiles リポジトリ。シンボリックリンクベースで設定ファイルを管理する。OS判定（`uname -s`）で macOS 固有の設定（Karabiner, pbcopy, iTerm2 等）を分岐する。

## よく使うコマンド

```bash
# 開発環境（tmux）を開く
dev <path>       # フォルダを開く（無ければ作る）
dev              # 直近に使っていたフォルダへ戻る
dev restart      # 全フォルダを同じ構成で作り直す

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
- **tmux** (`.tmux.conf`): vim風キーバインド。`tmux-dev.sh`（`dev` コマンド）が開発環境を構築し、`tmux-sidebar.sh` が左端の常駐サイドバーを描画する

### tmux × Claude Code 並列運用

複数プロジェクトでClaude Codeを同時並行で動かし、人間の注意を最適配分するための仕組み。設計思想は「待っている → 気づく → 切り替える → 対応する」のループを最小認知負荷で回すこと。

#### 2階層モデル

| 呼び名 | tmux の実体 | 例 |
| --- | --- | --- |
| フォルダ | セッション | `dotfiles`, `kagisuru-web` |
| セッション | ウィンドウ | `claude1`, `claude2`, `lg`, `nv`, `sh1` |

セッションは1画面を占有し、中を `|` / `-` で自由にペイン分割できる。ウィンドウ名から起動コマンドを逆引きするので（`claude*` → Claude Code、`lg` → lazygit、`nv` → エディタ、それ以外 → シェル）、`dev restart` は同じ構成をそのまま復元できる。

#### 常駐サイドバー

各ウィンドウの左端28列に、全フォルダ→セッションのツリーを表示する（`tmux-sidebar.sh`）。

- ウィンドウごとに1プロセス走るが、描画するのは画面に出ているウィンドウのものだけ。内容が変わらないときは描画しないのでちらつかない
- 再描画は1秒ポーリング + フックからの SIGUSR1。**SIGUSR1 のハンドラはスクリプト先頭で張る**（既定動作がプロセス終了のため、起動直後にシグナルが飛ぶと死ぬ）
- ペインオプション `@sidebar` で識別し、`after-select-pane` フックがフォーカスを隣へ逃がす。表示専用でキー入力は受け取らない
- 生成は `split-window -fhb`。`-f`（ウィンドウ全体に対する分割）がないと作業ペインが複数あるときに左端へ入らない
- **未読/既読インジケーター**: ○＝動作中/既読、●＝未読（黄色点滅）。セッションを開くと中のClaudeがまとめて既読になる
- **既読ロック**: 確認済みのセッションが再通知で光り直す問題を防止する仕組み

#### キーバインド

| キー | 動作 |
| --- | --- |
| `prefix 1`〜`9` | フォルダを切り替え。続けて数字を押すとその中のN番目のセッションへ（2キージャンプ、1秒で解除） |
| `prefix h` / `l` | 同じフォルダ内でセッションを前後に移動 |
| `prefix H` / `L` | フォルダを前後に移動 |
| `prefix c` / `t` / `g` / `e` | セッションを追加（claudeN / シェル / lazygit / エディタ）。`lg` と `nv` は既にあればそこへ移動 |
| `prefix o` | ポップアップでフォルダを追加。`TMUX_DEV_ROOTS`（既定 `~/Developer`）から始まり、Tab で階層を辿れる |
| `prefix x` / `X` | セッションを閉じる / フォルダごと閉じる |
| `prefix b` | サイドバーの表示切替 |
| `prefix Tab` | ペインを巡回（サイドバーは飛ばす） |

サイドバーのクリックでもフォルダ・セッションを切り替えられる。

#### フォルダ追加ポップアップ

`prefix o` は `display-popup` の中で `ZDOTDIR=dev-pick/` の zsh を起動し、fzf-tab のディレクトリ補完をそのまま使う（`dev-pick/.zshrc`）。通常の `~/.zshrc` は読まないので起動が速い。

- 起動時に `zle-line-init` から `dev <ルート>/` を入力して `fzf-tab-complete` を呼ぶ
- `continuous-trigger 'tab'` → Tab で選択中の候補までのパスが入力され、その先の補完が続く
- `accept-line 'enter'` → Enter で `dev <path>` がそのまま実行される（どちらも fzf の `--expect` に渡るキー名）
- `dev` は成功したときだけ `exit` する。失敗時はポップアップを残してメッセージを読めるようにしている

#### 実装上の注意

`run-shell` やキーバインドに渡される `TMUX_PANE` / `#{session_name}` は、**クライアントが今見ているペインとは限らない**（特に `switch-client` の直後）。そのためスクリプト側は `#{client_session}` を起点に対象を解決している（`tmux-dev.sh` の `current_session` / `current_window`）。同じ理由で `tmux-cycle-pane.sh` や `tmux-responsive-layout.sh` も対象を明示指定する。

### セキュリティ

- `.env` ファイルはgitignore対象。APIキーやトークンはすべて `.env` で管理
- `hooks/pre-commit` が `.sensitive-words` に定義された機密ワードのコミットをブロックする

### 規約

- ドキュメント・コメントは日本語で記述する
- macOS: Homebrew の追加・削除は `Brewfile` を直接編集したあとに、homebrewのコマンドを実行する
- Ubuntu: apt パッケージの追加・削除は `Aptfile` を直接編集する
- 新しい設定ファイルを追加する場合は `setup.sh` にシンボリックリンクの定義も追加する
