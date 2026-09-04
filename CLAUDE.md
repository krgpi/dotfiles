# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリ概要

macOS / Ubuntu 両対応の dotfiles リポジトリ。シンボリックリンクベースで設定ファイルを管理する。OS判定（`uname -s`）で macOS 固有の設定（Karabiner, pbcopy, iTerm2 等）を分岐する。

## よく使うコマンド

```bash
# 開発環境（tmux）を開く
dev <path>          # フォルダを開く（無ければ作る）
dev                 # 直近に使っていたフォルダへ戻る
dev restart         # tmux 設定を読み直す（作業中のペインはそのまま）
dev restart --full  # tmux ごと落として全フォルダを同じ構成で作り直す

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
- **Neovim** (`nvim/`): lazy.nvim でプラグイン管理。エントリポイントは `nvim/init.lua`、設定は `nvim/lua/options/`、プラグインは `nvim/lua/plugins/`。telescope と mason は起動時に読まず、キーマップ（`keys`）とバッファを開いたとき（`event`）まで遅らせている。`nvim/lua/tmux_dev.lua` は `tmux-picker.sh` の一覧を telescope に流すだけのモジュール（`<leader>fp`）
- **Claude Code** (`claude/`): グローバル設定・カスタムコマンド（ask-gemini, mk-pr, x-search）・hooks（tmux未読通知, Prettier自動整形, ccusage）
- **macOS のシステム設定** (`macos.sh`): Dock・Finder・トラックパッド・スクリーンショット・メニューバーなどの `defaults` を一括適用する。`setup.sh` からは実行せず手動で叩く。ウィンドウ位置やマシン固有の識別子など環境依存の値は持たない
- **自動更新** (`dotfiles-update.sh`): 1日1回、ターミナル起動時に zsh-defer 経由でバックグラウンド実行。`brew update` + `brew upgrade --formula` と fzf-tab / zsh-defer の `git pull` を行う。cask は起動中アプリの差し替えを避けるため件数通知のみ。結果は次回のターミナル起動時に一度だけ表示される。`up` で即時実行でき、その場に結果を出力する。実行履歴（更新されたコミット一覧を含む）は `~/.cache/dotfiles-update/last.log` に追記される（直近500行を保持）
- **tmux** (`.tmux.conf`): vim風キーバインド。`tmux-dev.sh`（`dev` コマンド）が開発環境を構築し、`tmux-picker.sh` が `prefix Space` の一覧を、`tmux-status-waiting.sh` がステータス右の未読表示を担当する
- **yabai / skhd** (`.yabairc`, `.skhdrc`): macOS のタイル型ウィンドウマネージャとホットキーデーモン。macOS でのみリンクする。`.yabairc` は yabai が起動時に実行するので実行権限が必要。既定のレイアウトは `float` でタイルしない。`shift + alt - t` が `yabai-toggle-tiling.sh` を呼び、今いるスペースだけを `bsp` に切り替える（もう一度押すか yabai を再起動するまでタイルされ続ける）。タイル中のウィンドウが1枚だけのときは `yabai-solo-padding.sh` が signal 経由で左右に余白を足す（上限幅は `YABAI_SOLO_MAX_WIDTH`、既定 1600）。ウィンドウのリサイズは `alt + hjkl`（shift で拡大方向）に集約してあり、タイルでもフロートでも同じキーで効く。フロート時に幅を段階で決めたいときは `ctrl + alt` のキーから `yabai-float-size.sh` を呼ぶ。アクセシビリティでウィンドウを監視する他のアプリ（Swift-Quit など）が動いていると yabai が `window_destroyed` を受け取れなくなり、ウィンドウを閉じても残りが広がらない（スペースを行き来すると埋まる）。`yabai -m config debug_output on` にして `/tmp/yabai_$USER.out.log` に `WINDOW_DESTROYED` が出るかで切り分ける

### tmux × Claude Code 並列運用

複数プロジェクトでClaude Codeを同時並行で動かし、人間の注意を最適配分するための仕組み。設計思想は「待っている → 気づく → 切り替える → 対応する」のループを最小認知負荷で回すこと。

このうち**常時表示が要るのは「気づく」だけ**で、「切り替える」は押した瞬間だけ一覧が見えれば足りる。そのため一覧はピッカーに寄せてある。以前は左端36列に常駐サイドバーを描いていたが、全ウィンドウで画面の2割を固定的に取るうえ、サイドバーペインがウィンドウを生かし続けるので作業ペインを `exit` しても空のウィンドウが閉じず、一覧にゴミが溜まっていた。描画のちらつき・fork 数・幅計算といった作り込みもすべてこの常駐が原因だったので、まとめて畳んでいる。

#### モデル

全ウィンドウ（`claude1`, `claude2`, `nv`, `sh1` ...）は `dev` 専用の**1つの tmux セッション**（既定名 `dev`、`TMUX_DEV_SESSION` で変更可）に入る。「フォルダ」は tmux 上の実体ではなく、**各ウィンドウのアクティブペインが今いるパス**でピッカーがその場でグルーピングして見せているだけの表示上の概念。同じパスにいるウィンドウが1つのグループになり、`cd` すればウィンドウはそのまま別グループへ移る。

`dev <path>` の既定構成は Claude 1 つ、nvim 1 つ、空のターミナル 1 つ（`claude1` / `nv` / `sh1`）。同じパスが既に開いていれば新規に作らずそこへジャンプする。**lazygit と diff は nvim 側（`lazygit.nvim` / `diffview`）に集約しているので専用ウィンドウを持たない**。

ウィンドウは1画面を占有し、中を `|` / `-` で自由にペイン分割できる。ウィンドウ名から起動コマンドを逆引きするので（`claude*` → Claude Code、`nv` → エディタ、それ以外 → シェル）、`dev restart --full` は同じ構成をそのまま復元できる。ただし `claude*` のウィンドウでは Claude が毎回起動し直されるので、設定を変えただけなら作業ペインに触らない `dev restart` を使う。

#### 一覧（ピッカー）

`prefix Space` で `tmux-picker.sh` を `display-popup` に出す。パスでグルーピングした一覧の作り方はここに集約してあり、tmux 側（fzf）と nvim 側（telescope、`<leader>fp`）が同じ `list` を読む。

- 並ぶのはウィンドウ名ではなく**中で何が起きているか**。Claude Code は `pane_title` に出る `✳ <作業概要>`（まだ何もしていなければ `claude`）、それ以外のウィンドウはアクティブペインの `pane_current_command`（シェルのままなら `zsh`）。`claude1` や `sh1` といった dev が付けた名前は表示しない
- **Claude の判定はペインタイトルの `✳`**。Claude Code はプロセス名がバージョン番号（例 `2.1.238`）になるため `pane_current_command` では見分けられない
- ただし `✳` は Claude を抜けたあとも残ることがあるので、**そのペインがシェルに戻っていたら終了したものとして扱う**。ウィンドウ名が `claude*` かどうかは判定に使わない（使うと `/exit` したあとも `○` が残り続ける）
- グループの表示名はパスの basename。同じ basename のパスが複数あるときだけ親ディレクトリ名を足して区別する
- git 状態は fzf / telescope のプレビューで `git status -sb` を出すだけ。自前でキャッシュを持たない（一覧を出した瞬間にしか要らないため）
- `ctrl-x` でそのウィンドウを閉じてリロードする
- 出力は `<window_id> TAB <パス> TAB <表示>`。fzf には 3 列目だけ見せ、1 列目で `select-window`、2 列目でプレビューを引く。`NO_COLOR` が設定されていれば色を付けない（nvim から読むときに使う）

#### 未読の気づき

Claude Code の hooks（`claude-marketplace/karaage-tools/tmux-sidebar-notify.sh`）が `/tmp/claude-waiting-<pane_id>` を置き、`tmux-status-waiting.sh` がそれをフォルダ名に畳んでステータス右へ `● dotfiles stickies` と出す。未読が無ければ何も出さない。

- hooks 側が最後に `tmux refresh-client -S` を叩くので、`status-interval`（2秒）を待たずに反映される
- **既読ロック**: 確認済みのウィンドウが再通知で光り直すのを防ぐ。ウィンドウを開くと中の Claude がまとめて既読になり（`after-select-window` フック）、次のプロンプト送信時に `UserPromptSubmit` フックがロックを外す

#### キーバインド

| キー | 動作 |
| --- | --- |
| `prefix Space` | フォルダ/ウィンドウのピッカー（`ctrl-x` でそのウィンドウを閉じる） |
| `prefix h` / `l` | 同じパス内でウィンドウを前後に移動 |
| `prefix H` / `L` | フォルダ（パスのグループ）を前後に移動 |
| `prefix c` / `t` / `e` | 現在のウィンドウと同じパスにウィンドウを追加（claudeN / シェル / エディタ）。`nv` は既にあればそこへ移動 |
| `prefix x` / `X` | ウィンドウを閉じる / 同じパスのウィンドウをまとめて閉じる |
| `prefix Tab` | ペインを巡回 |

新しいパスを開くのに専用の操作はなく、どのシェルからでも `dev <path>` を打てばそのまま開く（既に開いていればジャンプするだけ）。

#### 実装上の注意

`run-shell` やキーバインドに渡される `TMUX_PANE` / `#{session_name}` は、**クライアントが今見ているペインとは限らない**（特に `switch-client` の直後）。そのためスクリプト側は `#{client_session}` を起点に対象を解決している（`tmux-dev.sh` の `current_window`）。

グループ判定用のパス比較は**物理パス**（`pwd -P`）で行う。tmux の `pane_current_path` は常に symlink を解決した物理パスを返すため、`dev <path>` 側が論理パス（`cd && pwd`）のまま比較すると、symlink 越しのパス（macOS の `/tmp` など）で同じ場所を毎回別グループとして開き直してしまう。

### セキュリティ

- `.env` ファイルはgitignore対象。APIキーやトークンはすべて `.env` で管理
- `hooks/pre-commit` が `.sensitive-words` に定義された機密ワードのコミットをブロックする

### 規約

- ドキュメント・コメントは日本語で記述する
- macOS: Homebrew の追加・削除は `Brewfile` を直接編集したあとに、homebrewのコマンドを実行する
- Ubuntu: apt パッケージの追加・削除は `Aptfile` を直接編集する
- 新しい設定ファイルを追加する場合は `setup.sh` にシンボリックリンクの定義も追加する
