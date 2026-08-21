#!/bin/bash

# dev コマンド本体
#
# 階層構造:
#   フォルダ  = tmux セッション（プロジェクトのディレクトリ名）
#   セッション = tmux ウィンドウ（claude1, claude2, lg, nv, sh1 ...）
#   各ウィンドウの左端には常駐サイドバー（tmux-sidebar.sh）が入る
#
# 使い方:
#   dev              直近に使っていたフォルダへ戻る
#   dev <path>       フォルダを開く（無ければ作る）
#   dev restart      tmux 設定とサイドバーを読み直す（作業中のペインはそのまま）
#   dev restart --full
#                    全フォルダを保存してから tmux を再起動し、同じ構成で復元する
#   dev pick         fzf でフォルダを選んで開く（prefix + o のポップアップから呼ばれる）
#
# 以下は .tmux.conf のキーバインド/フックから呼ばれる内部サブコマンド:
#   new <kind> / jump-folder <n> / jump-window <n> / close-window / close-folder
#   toggle-sidebar / ensure-sidebar / fix-width / on-select-pane / sidebar-click / jump-timeout

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SIDEBAR_SCRIPT="$DOTFILES_DIR/tmux-sidebar.sh"
SIDEBAR_WIDTH="${TMUX_SIDEBAR_WIDTH:-36}"
CLAUDE_CMD="${TMUX_DEV_CLAUDE_CMD:-claude}"
EDITOR_CMD="${TMUX_DEV_EDITOR_CMD:-nvim .}"
DEV_ROOTS="${TMUX_DEV_ROOTS:-$HOME/Developer}"
ROWS_FILE="/tmp/tmux-sidebar-rows"
STATE_FILE="/tmp/tmux-dev-restart"

# ── 共通ヘルパ ────────────────────────────────────────────────

# tmux のターゲット指定で誤解釈される文字をセッション名から取り除く
sanitize() {
    printf '%s' "$1" | tr '.: ' '___'
}

# サイドバーを即座に描き直す
# 画面に出ているのは今いるウィンドウのサイドバーだけなので、そこにだけシグナルを送る
# （pkill で全部に送ると裏のウィンドウのぶんまで起きて無駄に重くなる）
refresh_sidebar() {
    local pid
    pid="$(tmux list-panes -t "$(current_window)" -F '#{pane_pid}|#{@sidebar}' 2>/dev/null \
        | awk -F'|' '$2 == "1" { print $1; exit }')"
    [ -n "$pid" ] && kill -USR1 "$pid" 2>/dev/null
    tmux refresh-client -S 2>/dev/null || true
}

# キーバインドから呼ばれたときの「今いるフォルダ」を返す
# prefix + 数字でフォルダを切り替えた直後は #{session_name} が切り替え前のペインを指すため、
# クライアントのセッションを優先する
current_session() {
    local session
    session="$(tmux display-message -p '#{client_session}' 2>/dev/null)"
    [ -n "$session" ] || session="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
    printf '%s' "$session"
}

# 同じく「今いるセッション（ウィンドウ）」
current_window() {
    local win
    win="$(tmux display-message -p -t "$(current_session):" '#{window_id}' 2>/dev/null)"
    [ -n "$win" ] || win="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
    printf '%s' "$win"
}

sidebar_pane() {
    tmux list-panes -t "$1" -F '#{pane_id}|#{@sidebar}' 2>/dev/null \
        | awk -F'|' '$2 == "1" { print $1; exit }'
}

ensure_sidebar() {
    local win="${1:-}"
    [ -n "$win" ] || win="$(current_window)"
    [ -n "$win" ] || return 0
    [ -n "$(sidebar_pane "$win")" ] && return 0
    # -f はウィンドウ全体に対する分割。これがないと「アクティブペインの左」に入ってしまい、
    # 作業ペインが複数あるウィンドウで左端に来ない
    tmux split-window -fhb -l "$SIDEBAR_WIDTH" -d -t "$win" "$SIDEBAR_SCRIPT" 2>/dev/null
}

# ウィンドウ名の種別からデフォルトの起動コマンドを返す
cmd_of() {
    case "$1" in
        claude) printf '%s' "$CLAUDE_CMD" ;;
        lg)     printf 'lazygit' ;;
        nv)     printf '%s' "$EDITOR_CMD" ;;
        *)      printf '' ;;
    esac
}

# ウィンドウ名から種別を逆引きする（restart の復元用）
# unknown は dev が付けた名前ではないもの（tmux の自動命名や手動リネーム）
kind_of() {
    case "$1" in
        claude*)       printf 'claude' ;;
        lg)            printf 'lg' ;;
        nv)            printf 'nv' ;;
        sh | sh[0-9]*) printf 'term' ;;
        *)             printf 'unknown' ;;
    esac
}

# 同じ接頭辞のウィンドウ名を数えて次の連番を返す（claude1 → claude2）
next_name() {
    local session="$1" prefix="$2" max=0 name n
    while IFS= read -r name; do
        case "$name" in
            "$prefix"*)
                n="${name#$prefix}"
                case "$n" in
                    '' | *[!0-9]*) ;;
                    *) [ "$n" -gt "$max" ] && max="$n" ;;
                esac
                ;;
        esac
    done < <(tmux list-windows -t "=$session" -F '#{window_name}' 2>/dev/null)
    printf '%s%d' "$prefix" $((max + 1))
}

name_of() {
    local session="$1"
    case "$2" in
        claude) next_name "$session" claude ;;
        lg)     printf 'lg' ;;
        nv)     printf 'nv' ;;
        *)      next_name "$session" sh ;;
    esac
}

find_window() {
    tmux list-windows -t "=$1" -F '#{window_name}|#{window_id}' 2>/dev/null \
        | awk -F'|' -v n="$2" '$1 == n { print $2; exit }'
}

# ウィンドウを1つ作り、サイドバーを付けてコマンドを流す
spawn_window() {
    local session="$1" name="$2" cmd="$3" dir="$4" focus="$5" wid
    wid="$(tmux new-window -d -t "=$session:" -n "$name" -c "$dir" -P -F '#{window_id}' 2>/dev/null)"
    [ -n "$wid" ] || return 1
    ensure_sidebar "$wid"
    [ -n "$cmd" ] && tmux send-keys -t "$wid" "$cmd" C-m
    [ "$focus" = "1" ] && tmux select-window -t "$wid"
    printf '%s' "$wid"
}

# ── フォルダ（tmux セッション）の作成 ─────────────────────────

# 指定したウィンドウ名リストでフォルダを作る（リストが空ならデフォルト構成）
create_folder() {
    local dir="$1" wins="${2:-}" session first_win name cmd first=1
    session="$(sanitize "$(basename "$dir")")"

    # 名前を付けていないウィンドウが1つだけのフォルダは、dev で作ったものではない
    # （tmux の自動命名。旧レイアウトからの移行など）ので既定構成で組み直す
    if [ -n "$wins" ]; then
        set -- $wins
        [ "$#" = "1" ] && [ "$(kind_of "$1")" = "unknown" ] && wins=""
    fi

    # 既定は Claude 1 つと空のターミナル 2 つ。lazygit やエディタは
    # 空のターミナルで好きに起動すればよく、サイドバーにはその中身が出る
    [ -z "$wins" ] && wins="claude1 sh1 sh2"

    for name in $wins; do
        cmd="$(cmd_of "$(kind_of "$name")")"
        if [ "$first" = "1" ]; then
            tmux new-session -d -s "$session" -c "$dir" -n "$name" 2>/dev/null || return 1
            first_win="$(tmux list-windows -t "=$session" -F '#{window_id}' 2>/dev/null | head -1)"
            ensure_sidebar "$first_win"
            [ -n "$cmd" ] && tmux send-keys -t "$first_win" "$cmd" C-m
            first=0
        else
            spawn_window "$session" "$name" "$cmd" "$dir" 0 >/dev/null
        fi
    done

    [ -n "$first_win" ] && tmux select-window -t "$first_win"
    return 0
}

open_folder() {
    local dir session
    dir="$(cd "$1" 2>/dev/null && pwd)" || {
        echo "エラー: ディレクトリが見つかりません: $1" >&2
        return 1
    }
    session="$(sanitize "$(basename "$dir")")"

    if tmux has-session -t "=$session" 2>/dev/null; then
        echo "フォルダ '$session' は既に開いています"
    else
        create_folder "$dir" || {
            echo "エラー: フォルダ '$session' を作成できませんでした" >&2
            return 1
        }
        echo "フォルダ '$session' を開きました"
    fi

    refresh_sidebar
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "=$session"
    else
        tmux attach-session -t "=$session"
    fi
}

# ── サブコマンド ──────────────────────────────────────────────

cmd_new() {
    local kind="${1:-term}" session dir name existing
    session="$(current_session)"
    [ -n "$session" ] || return 0
    dir="$(tmux display-message -p -t "$session:" '#{pane_current_path}' 2>/dev/null)"
    [ -d "$dir" ] || dir="$(tmux display-message -p -t "$session:" '#{session_path}' 2>/dev/null)"

    # lg / nv はフォルダに1つあれば足りるので、既にあればそこへ移動する
    case "$kind" in
        lg | nv)
            existing="$(find_window "$session" "$kind")"
            if [ -n "$existing" ]; then
                tmux select-window -t "$existing"
                refresh_sidebar
                return 0
            fi
            ;;
    esac

    name="$(name_of "$session" "$kind")"
    spawn_window "$session" "$name" "$(cmd_of "$kind")" "$dir" 1 >/dev/null
    refresh_sidebar
}

cmd_jump_folder() {
    local target
    target="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sed -n "${1}p")"
    [ -n "$target" ] || return 0
    tmux switch-client -t "=$target"
    # 続けて数字を押せばそのフォルダ内のセッションへ飛べるようにする
    # 何も押されなければ jump-timeout が root テーブルに戻す
    tmux switch-client -T dev-jump
    tmux run-shell -b -d 1 "$DOTFILES_DIR/tmux-dev.sh jump-timeout"
    refresh_sidebar
}

cmd_jump_window() {
    local session wid
    session="$(current_session)"
    wid="$(tmux list-windows -t "=$session" -F '#{window_id}' 2>/dev/null | sed -n "${1}p")"
    [ -n "$wid" ] || return 0
    tmux select-window -t "$wid"
    refresh_sidebar
}

# prefix + 数字のあとのセッション番号待ちを一定時間で打ち切る
cmd_jump_timeout() {
    tmux if-shell -F '#{==:#{client_key_table},dev-jump}' 'switch-client -T root'
}

cmd_toggle_sidebar() {
    local win pane
    win="$(current_window)"
    pane="$(sidebar_pane "$win")"
    if [ -n "$pane" ]; then
        tmux kill-pane -t "$pane"
    else
        ensure_sidebar "$win"
    fi
}

# ペイン分割やリサイズで崩れたサイドバーの幅を戻す
cmd_fix_width() {
    local win="${1:-}" pane width
    [ -n "$win" ] || win="$(current_window)"
    pane="$(sidebar_pane "$win")"
    [ -n "$pane" ] || return 0
    [ "$(tmux display-message -p -t "$win" '#{window_zoomed_flag}' 2>/dev/null)" = "1" ] && return 0
    width="$(tmux display-message -p -t "$pane" '#{pane_width}' 2>/dev/null)"
    [ "$width" = "$SIDEBAR_WIDTH" ] && return 0
    tmux resize-pane -t "$pane" -x "$SIDEBAR_WIDTH" 2>/dev/null
}

# Claude ペインの未読を消す。既読ロックは idle_prompt の再発火を抑えるためのもので、
# 次のプロンプト送信時に UserPromptSubmit フックがクリアする
# 既読にできたときだけ 0 を返す（呼び出し側が再描画の要否を判断できるように）
mark_read() {
    local pane="$1"
    [ -f "/tmp/claude-waiting-${pane}" ] || return 1
    rm -f "/tmp/claude-waiting-${pane}"
    touch "/tmp/claude-read-${pane}"
    return 0
}

# after-select-pane フック: Claude ペインを開いたら既読にする
# （サイドバーからのフォーカス追い出しは .tmux.conf 側で tmux だけで済ませている）
# 未読を消したときだけ描き直す。ただのペイン移動で起こすと再描画が頻繁すぎるので、
# 表示の追従は 1 秒ポーリングに任せる
# 既読にできなかったときも 0 で返す。run-shell は非ゼロを失敗とみなして
# 「returned 1」をペインに出してしまう
cmd_on_select_pane() {
    local pane="${1:-}"
    [ -n "$pane" ] || return 0
    mark_read "$pane" && refresh_sidebar
    return 0
}

# after-select-window フック: 開いたセッション内の Claude をまとめて既読にする
# （ウィンドウを切り替えても after-select-pane は発火しないため別に必要）
cmd_on_select_window() {
    local win pane
    win="$(current_window)"
    [ -n "$win" ] || return 0
    while IFS= read -r pane; do
        [ -n "$pane" ] && mark_read "$pane"
    done < <(tmux list-panes -t "$win" -F '#{pane_id}|#{@sidebar}' 2>/dev/null | awk -F'|' '$2 != "1" { print $1 }')
    # セッションを移るとアクティブ表示が変わるので、こちらは常に描き直す
    refresh_sidebar
}

cmd_sidebar_click() {
    local row="${1:-}" r kind target session
    [ -n "$row" ] && [ -f "$ROWS_FILE" ] || return 0
    while IFS='|' read -r r kind target; do
        [ "$r" = "$row" ] || continue
        case "$kind" in
            s)
                tmux switch-client -t "=$target"
                ;;
            w)
                session="$(tmux display-message -p -t "$target" '#{session_name}' 2>/dev/null)"
                [ -n "$session" ] && tmux switch-client -t "=$session"
                tmux select-window -t "$target"
                ;;
        esac
        refresh_sidebar
        return 0
    done < "$ROWS_FILE"
}

# フォルダ選択ポップアップ。fzf-tab のディレクトリ補完をそのまま使いたいので、
# find + fzf ではなく専用の最小 zsh 環境（dev-pick/.zshrc）を起動する
cmd_pick() {
    TMUX_DEV_ROOTS="$DEV_ROOTS" ZDOTDIR="$DOTFILES_DIR/dev-pick" exec zsh -i
}

# ガワ（tmux 設定とサイドバー）だけ読み直す。作業ペインには触らないので
# Claude や nvim は動いたまま。構成から作り直したいときは --full
cmd_restart() {
    local win pane

    if [ "${1:-}" = "--full" ]; then
        cmd_rebuild
        return
    fi

    if ! tmux has-session 2>/dev/null; then
        echo "エラー: tmux が起動していません" >&2
        return 1
    fi

    tmux source-file "$HOME/.tmux.conf" 2>/dev/null

    # サイドバーはスクリプトを書き換えても走り続けるので、ペインごと入れ替える
    while IFS= read -r win; do
        pane="$(sidebar_pane "$win")"
        [ -n "$pane" ] && tmux kill-pane -t "$pane"
        ensure_sidebar "$win"
    done < <(tmux list-windows -a -F '#{window_id}' 2>/dev/null)

    "$DOTFILES_DIR/tmux-responsive-layout.sh" 2>/dev/null

    echo "設定とサイドバーを読み直しました"
}

cmd_rebuild() {
    local session path wins dir

    : > "$STATE_FILE"
    while IFS='|' read -r session path; do
        [ -n "$session" ] || continue
        [ -d "$path" ] || continue
        wins="$(tmux list-windows -t "=$session" -F '#{window_name}' 2>/dev/null | tr '\n' ' ')"
        printf '%s\t%s\n' "$path" "$wins" >> "$STATE_FILE"
    done < <(tmux list-sessions -F '#{session_name}|#{session_path}' 2>/dev/null)

    if [ ! -s "$STATE_FILE" ]; then
        echo "エラー: 復元するフォルダがありません" >&2
        rm -f "$STATE_FILE"
        return 1
    fi

    echo "復元対象:"
    cut -f1 "$STATE_FILE"

    # tmux 内から実行された場合は detach して元のシェルに制御を戻し、そこで再実行する
    if [ -n "$TMUX" ]; then
        tmux detach-client -E "exec '$DOTFILES_DIR/tmux-dev.sh' restart --full"
        return 0
    fi

    tmux kill-server 2>/dev/null
    sleep 0.5

    while IFS=$'\t' read -r dir wins; do
        [ -d "$dir" ] || continue
        echo "復元中: $dir"
        create_folder "$dir" "$wins"
    done < "$STATE_FILE"
    rm -f "$STATE_FILE"

    local first
    first="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1)"
    [ -n "$first" ] && tmux attach-session -t "=$first"
}

# 引数なし: 新規作成せず、直近にアタッチされていたフォルダへ戻る
cmd_last() {
    local current target

    if [ -n "$TMUX" ]; then
        current="$(tmux display-message -p '#{session_name}' 2>/dev/null)"
    else
        current=""
    fi

    # session_last_attached の降順で、現在のフォルダを除いた直近を選ぶ
    # 未アタッチのセッションでは session_last_attached が空になるため0として扱う
    target="$(tmux list-sessions -F "#{session_last_attached}"$'\t'"#{session_name}" 2>/dev/null \
        | awk -F'\t' -v cur="$current" '$2 != cur { printf "%d\t%s\n", $1, $2 }' \
        | sort -rn \
        | head -1 \
        | cut -f2-)"

    if [ -z "$target" ]; then
        echo "開いているフォルダがありません（'dev .' で現在のディレクトリを開けます）" >&2
        return 1
    fi

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "=$target"
    else
        tmux attach-session -t "=$target"
    fi
}

# ── ディスパッチ ──────────────────────────────────────────────

case "${1:-}" in
    '')              cmd_last ;;
    restart)         cmd_restart "$2" ;;
    pick)            cmd_pick ;;
    new)             cmd_new "$2" ;;
    jump-folder)     cmd_jump_folder "$2" ;;
    jump-window)     cmd_jump_window "$2" ;;
    jump-timeout)    cmd_jump_timeout ;;
    close-window)    tmux kill-window ;;
    close-folder)    tmux kill-session ;;
    toggle-sidebar)  cmd_toggle_sidebar ;;
    ensure-sidebar)  ensure_sidebar "$2" ;;
    fix-width)       cmd_fix_width "$2" ;;
    on-select-pane)  cmd_on_select_pane "$2" ;;
    on-select-window) cmd_on_select_window ;;
    sidebar-click)   cmd_sidebar_click "$2" ;;
    refresh)         refresh_sidebar ;;
    *)               open_folder "$1" ;;
esac
