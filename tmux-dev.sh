#!/bin/bash

# dev コマンド本体
#
# 全ウィンドウが1つの tmux セッション（GLOBAL_SESSION）に入る。
# 「フォルダ」という概念はもう tmux 上の実体ではなく、各ウィンドウの
# アクティブペインが今いるディレクトリ（カレントパス）で都度グルーピングして
# 見せているだけ。同じパスのウィンドウが1つのグループになる。
#
# 一覧は常駐させない。prefix + Space のピッカー（tmux-picker.sh）が
# 必要なときだけグルーピングして出し、「Claude が待っている」ことに気づく役は
# ステータス右の ●（tmux-status-waiting.sh）が担当する。
#
# 使い方:
#   dev              直近のウィンドウへ戻る（tmux にアタッチ/スイッチするだけ）
#   dev <path>       そのパスのウィンドウ群を開く（無ければ作る）
#   dev restart      tmux 設定を読み直す（作業中のペインはそのまま）
#   dev restart --full
#                    全ウィンドウを保存してから tmux を再起動し、同じ構成で復元する
#
# 以下は .tmux.conf のキーバインド/フックから呼ばれる内部サブコマンド:
#   new <kind> / cycle-window <prev|next> / cycle-folder <prev|next>
#   close-window / close-folder / on-select-pane / on-select-window

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_CMD="${TMUX_DEV_CLAUDE_CMD:-claude}"
EDITOR_CMD="${TMUX_DEV_EDITOR_CMD:-nvim .}"
GLOBAL_SESSION="${TMUX_DEV_SESSION:-dev}"
STATE_FILE="/tmp/tmux-dev-restart"

# ── 共通ヘルパ ────────────────────────────────────────────────

# ステータスバー（未読の ●）を即座に描き直す
refresh_status() {
    tmux refresh-client -S 2>/dev/null || true
}

# 「今いるウィンドウ」を返す
# run-shell に渡される TMUX_PANE / #{session_name} はクライアントが今見ている
# ペインとは限らないため、クライアントのセッション経由で解決する
current_window() {
    local win
    win="$(tmux display-message -p -t "=$GLOBAL_SESSION:" '#{window_id}' 2>/dev/null)"
    [ -n "$win" ] || win="$(tmux display-message -p '#{window_id}' 2>/dev/null)"
    printf '%s' "$win"
}

# 指定ウィンドウの「所属パス」= アクティブペインのカレントパス
window_dir() {
    local win="$1" dir
    dir="$(tmux list-panes -t "$win" -F '#{pane_active}|#{pane_current_path}' 2>/dev/null \
        | awk -F'|' '$1 == "1" { print $2; exit }')"
    printf '%s' "$dir"
}

# GLOBAL_SESSION 内の全ウィンドウを「<パス>|<window_id>」で列挙する（tmux のウィンドウ順）
list_groups() {
    local wid d
    while IFS= read -r wid; do
        [ -n "$wid" ] || continue
        d="$(window_dir "$wid")"
        [ -n "$d" ] && printf '%s|%s\n' "$d" "$wid"
    done < <(tmux list-windows -t "=$GLOBAL_SESSION" -F '#{window_id}' 2>/dev/null)
}

# 同じパスのウィンドウの中から、指定した名前のウィンドウを探す
find_window_in_group() {
    local dir="$1" name="$2" d wid n
    while IFS='|' read -r d wid; do
        [ "$d" = "$dir" ] || continue
        n="$(tmux display-message -p -t "$wid" '#{window_name}' 2>/dev/null)"
        if [ "$n" = "$name" ]; then
            printf '%s' "$wid"
            return 0
        fi
    done < <(list_groups)
    return 1
}

# ウィンドウ名の種別からデフォルトの起動コマンドを返す
cmd_of() {
    case "$1" in
        claude) printf '%s' "$CLAUDE_CMD" ;;
        nv)     printf '%s' "$EDITOR_CMD" ;;
        *)      printf '' ;;
    esac
}

# ウィンドウ名から種別を逆引きする（restart の復元用）
# unknown は dev が付けた名前ではないもの（tmux の自動命名や手動リネーム）
kind_of() {
    case "$1" in
        claude*)       printf 'claude' ;;
        nv)            printf 'nv' ;;
        sh | sh[0-9]*) printf 'term' ;;
        *)             printf 'unknown' ;;
    esac
}

# 同じパスのウィンドウの中で、同じ接頭辞の名前を数えて次の連番を返す（claude1 → claude2）
next_name() {
    local dir="$1" prefix="$2" max=0 d wid name n
    while IFS='|' read -r d wid; do
        [ "$d" = "$dir" ] || continue
        name="$(tmux display-message -p -t "$wid" '#{window_name}' 2>/dev/null)"
        case "$name" in
            "$prefix"*)
                n="${name#$prefix}"
                case "$n" in
                    '' | *[!0-9]*) ;;
                    *) [ "$n" -gt "$max" ] && max="$n" ;;
                esac
                ;;
        esac
    done < <(list_groups)
    printf '%s%d' "$prefix" $((max + 1))
}

name_of() {
    local dir="$1"
    case "$2" in
        claude) next_name "$dir" claude ;;
        nv)     printf 'nv' ;;
        *)      next_name "$dir" sh ;;
    esac
}

# ウィンドウを1つ作ってコマンドを流す（常に GLOBAL_SESSION の中）
spawn_window() {
    local name="$1" cmd="$2" dir="$3" focus="$4" wid
    wid="$(tmux new-window -d -t "=$GLOBAL_SESSION:" -n "$name" -c "$dir" -P -F '#{window_id}' 2>/dev/null)"
    [ -n "$wid" ] || return 1
    [ -n "$cmd" ] && tmux send-keys -t "$wid" "$cmd" C-m
    [ "$focus" = "1" ] && tmux select-window -t "$wid"
    printf '%s' "$wid"
}

# ── グループ（同じパスのウィンドウ群）の作成 ──────────────────

# 指定したパスに、指定したウィンドウ名リストでウィンドウ群を作る
# （リストが空ならデフォルト構成: claude1 nv sh1）
# lazygit や diff は nvim 側（lazygit.nvim / diffview）に集約したので専用ウィンドウは持たない
create_group() {
    local dir="$1" wins="${2:-}" name cmd first_win group_first=""
    [ -z "$wins" ] && wins="claude1 nv sh1"

    for name in $wins; do
        cmd="$(cmd_of "$(kind_of "$name")")"
        if ! tmux has-session -t "=$GLOBAL_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$GLOBAL_SESSION" -c "$dir" -n "$name" 2>/dev/null || return 1
            first_win="$(tmux list-windows -t "=$GLOBAL_SESSION" -F '#{window_id}' 2>/dev/null | tail -1)"
            [ -n "$cmd" ] && tmux send-keys -t "$first_win" "$cmd" C-m
            [ -z "$group_first" ] && group_first="$first_win"
        else
            local wid
            wid="$(spawn_window "$name" "$cmd" "$dir" 0)"
            [ -z "$group_first" ] && group_first="$wid"
        fi
    done

    [ -n "$group_first" ] && tmux select-window -t "$group_first"
    return 0
}

open_group() {
    local dir wid
    # pwd -P で物理パスに解決する。tmux の pane_current_path も物理パスなので、
    # ここで論理パス（pwd）のままだと symlink 越しのパス（例: macOS の /tmp）で
    # 既存グループとの照合に失敗し、同じ場所を毎回新規に開いてしまう
    dir="$(cd "$1" 2>/dev/null && pwd -P)" || {
        echo "エラー: ディレクトリが見つかりません: $1" >&2
        return 1
    }

    wid="$(list_groups | awk -F'|' -v d="$dir" '$1 == d { print $2; exit }')"
    if [ -n "$wid" ]; then
        echo "'$dir' は既に開いています"
        tmux select-window -t "$wid"
    else
        create_group "$dir" || {
            echo "エラー: ウィンドウを作成できませんでした" >&2
            return 1
        }
        echo "'$dir' を開きました"
    fi

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "=$GLOBAL_SESSION"
    else
        tmux attach-session -t "=$GLOBAL_SESSION"
    fi
}

# ── サブコマンド ──────────────────────────────────────────────

cmd_new() {
    local kind="${1:-term}" win dir name existing
    win="$(current_window)"
    [ -n "$win" ] || return 0
    dir="$(window_dir "$win")"
    [ -n "$dir" ] || dir="$(tmux display-message -p -t "$win" '#{pane_current_path}' 2>/dev/null)"
    [ -n "$dir" ] || return 0

    # エディタはパスに1つあれば足りるので、既にあればそこへ移動する
    if [ "$kind" = "nv" ]; then
        existing="$(find_window_in_group "$dir" nv)"
        if [ -n "$existing" ]; then
            tmux select-window -t "$existing"
            return 0
        fi
    fi

    name="$(name_of "$dir" "$kind")"
    spawn_window "$name" "$(cmd_of "$kind")" "$dir" 1 >/dev/null
}

# 同じパスのウィンドウ内を前後に移動する（h / l）
cmd_cycle_window() {
    local dirn="$1" win dir wids=() w cur n idx target
    win="$(current_window)"
    [ -n "$win" ] || return 0
    dir="$(window_dir "$win")"
    [ -n "$dir" ] || return 0

    while IFS= read -r w; do
        [ -n "$w" ] && wids+=("$w")
    done < <(list_groups | awk -F'|' -v d="$dir" '$1 == d { print $2 }')

    n=${#wids[@]}
    [ "$n" -gt 1 ] || return 0
    for (( idx = 0; idx < n; idx++ )); do
        [ "${wids[idx]}" = "$win" ] && cur=$idx
    done
    [ -n "$cur" ] || return 0

    if [ "$dirn" = "prev" ]; then
        target="${wids[$(( (cur - 1 + n) % n ))]}"
    else
        target="${wids[$(( (cur + 1) % n ))]}"
    fi
    tmux select-window -t "$target"
}

# パス（グループ）を前後に切り替える（H / L）
cmd_cycle_folder() {
    local dirn="$1" win dir dirs=() d cur n idx target wid
    win="$(current_window)"
    [ -n "$win" ] || return 0
    dir="$(window_dir "$win")"
    [ -n "$dir" ] || return 0

    while IFS= read -r d; do
        [ -n "$d" ] && dirs+=("$d")
    done < <(list_groups | awk -F'|' '!seen[$1]++ { print $1 }' | sort)

    n=${#dirs[@]}
    [ "$n" -gt 1 ] || return 0
    for (( idx = 0; idx < n; idx++ )); do
        [ "${dirs[idx]}" = "$dir" ] && cur=$idx
    done
    [ -n "$cur" ] || return 0

    if [ "$dirn" = "prev" ]; then
        target="${dirs[$(( (cur - 1 + n) % n ))]}"
    else
        target="${dirs[$(( (cur + 1) % n ))]}"
    fi
    wid="$(list_groups | awk -F'|' -v d="$target" '$1 == d { print $2; exit }')"
    [ -n "$wid" ] || return 0
    tmux select-window -t "$wid"
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
# 既読にできなかったときも 0 で返す。run-shell は非ゼロを失敗とみなして
# 「returned 1」をペインに出してしまう
cmd_on_select_pane() {
    local pane="${1:-}"
    [ -n "$pane" ] || return 0
    mark_read "$pane" && refresh_status
    return 0
}

# after-select-window フック: 開いたウィンドウ内の Claude をまとめて既読にする
# （ウィンドウを切り替えても after-select-pane は発火しないため別に必要）
cmd_on_select_window() {
    local win pane
    win="$(current_window)"
    [ -n "$win" ] || return 0
    while IFS= read -r pane; do
        [ -n "$pane" ] && mark_read "$pane"
    done < <(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null)
    refresh_status
    return 0
}

# tmux 設定を読み直す。作業ペインには触らないので Claude や nvim は動いたまま。
# 構成から作り直したいときは --full
cmd_restart() {
    if [ "${1:-}" = "--full" ]; then
        cmd_rebuild
        return
    fi

    if ! tmux has-session 2>/dev/null; then
        echo "エラー: tmux が起動していません" >&2
        return 1
    fi

    tmux source-file "$HOME/.tmux.conf" 2>/dev/null
    refresh_status
    echo "設定を読み直しました"
}

# 同じパス（グループ）のウィンドウをすべて閉じる（X）
cmd_close_group() {
    local win dir wid
    win="$(current_window)"
    dir="$(window_dir "$win")"
    if [ -z "$dir" ]; then
        tmux kill-window
        return
    fi
    while IFS= read -r wid; do
        [ -n "$wid" ] && tmux kill-window -t "$wid" 2>/dev/null
    done < <(list_groups | awk -F'|' -v d="$dir" '$1 == d { print $2 }')
}

# 1つのパスぶんのウィンドウ名リストを、直前と同じパスならまとめて create_group に渡す。
# 名前を付けていないウィンドウが1つだけのパスは dev で作ったものではない
# （tmux の自動命名。旧レイアウトからの移行など）ので既定構成で組み直す
flush_group() {
    local dir="$1" wins="$2"
    [ -n "$dir" ] || return 0
    set -- $wins
    if [ "$#" = "1" ] && [ "$(kind_of "$1")" = "unknown" ]; then
        wins=""
    fi
    create_group "$dir" "$wins"
}

cmd_rebuild() {
    local wid dir name

    : > "$STATE_FILE"
    while IFS= read -r wid; do
        [ -n "$wid" ] || continue
        dir="$(window_dir "$wid")"
        [ -n "$dir" ] || continue
        [ -d "$dir" ] || continue
        name="$(tmux display-message -p -t "$wid" '#{window_name}' 2>/dev/null)"
        printf '%s\t%s\n' "$dir" "$name" >> "$STATE_FILE"
    done < <(tmux list-windows -a -F '#{window_id}' 2>/dev/null)

    if [ ! -s "$STATE_FILE" ]; then
        echo "エラー: 復元するウィンドウがありません" >&2
        rm -f "$STATE_FILE"
        return 1
    fi

    echo "復元対象:"
    cut -f1 "$STATE_FILE" | sort -u

    # tmux 内から実行された場合は detach して元のシェルに制御を戻し、そこで再実行する
    if [ -n "$TMUX" ]; then
        tmux detach-client -E "exec '$DOTFILES_DIR/tmux-dev.sh' restart --full"
        return 0
    fi

    tmux kill-server 2>/dev/null
    sleep 0.5

    local prev_dir="" wins=""
    while IFS=$'\t' read -r dir name; do
        if [ "$dir" != "$prev_dir" ]; then
            [ -n "$prev_dir" ] && flush_group "$prev_dir" "$wins"
            prev_dir="$dir"
            wins="$name"
        else
            wins="$wins $name"
        fi
    done < "$STATE_FILE"
    flush_group "$prev_dir" "$wins"
    rm -f "$STATE_FILE"

    tmux attach-session -t "=$GLOBAL_SESSION"
}

# 引数なし: 新規作成せず、tmux（GLOBAL_SESSION）へ戻る
cmd_last() {
    if ! tmux has-session -t "=$GLOBAL_SESSION" 2>/dev/null; then
        echo "開いているフォルダがありません（'dev .' で現在のディレクトリを開けます）" >&2
        return 1
    fi

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "=$GLOBAL_SESSION"
    else
        tmux attach-session -t "=$GLOBAL_SESSION"
    fi
}

# ── ディスパッチ ──────────────────────────────────────────────

case "${1:-}" in
    '')               cmd_last ;;
    restart)          cmd_restart "$2" ;;
    new)              cmd_new "$2" ;;
    cycle-window)     cmd_cycle_window "$2" ;;
    cycle-folder)     cmd_cycle_folder "$2" ;;
    close-window)     tmux kill-window ;;
    close-folder)     cmd_close_group ;;
    on-select-pane)   cmd_on_select_pane "$2" ;;
    on-select-window) cmd_on_select_window ;;
    refresh)          refresh_status ;;
    *)                open_group "$1" ;;
esac
