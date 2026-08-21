#!/bin/bash

# tmux サイドバー: フォルダ(tmuxセッション) → セッション(tmuxウィンドウ) のツリーを左端に常駐表示する
# 各ウィンドウの左端ペインで実行される。表示専用でフォーカスは受け取らない
# （フォーカスが来ても .tmux.conf の after-select-pane フックが隣のペインへ追い出す）
#
# 再描画は 1 秒ポーリング + SIGUSR1。内容が変わらないときは描画しないのでちらつかない。
# 非アクティブなウィンドウのサイドバーは画面に出ていないので描画をスキップする。
#
# クリック判定用の行マップ（行番号|種別|対象）を /tmp/tmux-sidebar-rows に書き出す
# （tmux-dev.sh sidebar-click が参照する）

ROWS_FILE="/tmp/tmux-sidebar-rows"

# Claude Code がペインタイトルの頭に付けるマーク（"✳ 作業概要" の形で出る）
CLAUDE_MARK='✳'
# 作業中でないときのタイトル。これは概要として扱わない
CLAUDE_IDLE='Claude Code'

[ -n "$TMUX_PANE" ] || exit 0

# SIGUSR1 のハンドラは何よりも先に張る
# （既定の動作はプロセス終了なので、起動直後に再描画シグナルが飛んでくると死んでしまう）
needs_render=0
trap 'needs_render=1' USR1

# 自ペインをサイドバーとして識別できるようにする
# @sidebar: ペイン単位（フォーカス追い出し判定用）
# @sidebar_pane: ウィンドウ単位（マウスクリックのターゲット判定用）
tmux set-option -p -t "$TMUX_PANE" @sidebar 1 2>/dev/null
tmux set-option -w -t "$TMUX_PANE" @sidebar_pane "$TMUX_PANE" 2>/dev/null

ESC=$'\033'
C_RESET="${ESC}[0m"
C_DIM="${ESC}[2m"
C_FOLDER="${ESC}[37;1m"
C_FOLDER_CUR="${ESC}[36;1m"
C_WIN_CUR="${ESC}[48;5;238m${ESC}[36;1m"
C_UNREAD="${ESC}[5;33;1m"
C_IDLE="${ESC}[2m"
C_HINT="${ESC}[2;37m"

printf '%s]2;sidebar%s\\' "$ESC" "$ESC"   # ペインタイトルを固定
printf '%s[?25l' "$ESC"                    # カーソル非表示
printf '%s[?7l' "$ESC"                     # 行の折り返しを止める（幅の計算がずれても崩さない）
printf '%s[?1000l%s[?1002l%s[?1003l%s[?1006l' "$ESC" "$ESC" "$ESC" "$ESC"  # マウスレポート無効

trap 'printf "%s[?25h%s[?7h" "$ESC" "$ESC"' EXIT

# 1文字の表示幅。ASCII は 1、それ以外は 2 とみなす
# bash 3.2 の printf は先頭バイトを符号付きで返すので、0-127 の外側を全角として扱う
char_width() {
    local code
    printf -v code '%d' "'$1" 2>/dev/null
    if [ "${code:-0}" -ge 32 ] && [ "${code:-0}" -le 126 ]; then
        printf 1
    else
        printf 2
    fi
}

str_width() {
    local s="$1" i n=0
    for (( i = 0; i < ${#s}; i++ )); do
        n=$(( n + $(char_width "${s:i:1}") ))
    done
    printf '%d' "$n"
}

# 表示幅で切り詰める（入りきらないときは末尾を ~ にする。~ 込みで max 幅に収める）
trunc() {
    local s="$1" max="$2" out="" i j cw w=0
    for (( i = 0; i < ${#s}; i++ )); do
        cw="$(char_width "${s:i:1}")"
        if [ $(( w + cw )) -gt "$max" ]; then
            while [ "$w" -ge "$max" ] && [ -n "$out" ]; do
                j=$(( ${#out} - 1 ))
                w=$(( w - $(char_width "${out:j:1}") ))
                out="${out:0:j}"
            done
            printf '%s~' "$out"
            return
        fi
        out="${out}${s:i:1}"
        w=$(( w + cw ))
    done
    printf '%s' "$out"
}

# ウィンドウ内の Claude の状態を "<state>|<summary>" で返す
#   state:   ! = 未読、. = 動作中/既読、空 = Claude なし
#   summary: ペインタイトルから取った作業概要（作業中でなければ空）
#
# Claude Code はプロセス名がバージョン番号（例: 2.1.238）になるため
# pane_current_command では判別できない。タイトル頭の ✳ で見分ける
win_claude() {
    local wid="$1" wname="$2" pid title found=0 unread=0 summary=""

    while IFS='|' read -r pid title; do
        [ -n "$pid" ] || continue
        [ -f "/tmp/claude-waiting-${pid}" ] && unread=1
        case "$title" in
            "${CLAUDE_MARK} "*)
                found=1
                title="${title#${CLAUDE_MARK} }"
                [ "$title" = "$CLAUDE_IDLE" ] || [ -n "$summary" ] || summary="$title"
                ;;
        esac
    done < <(printf '%s\n' "$DATA" | awk -F'|' -v w="$wid" '
        $2 == w && $6 != "1" {
            t = $8
            for (i = 9; i <= NF; i++) t = t "|" $i
            print $4 "|" t
        }')

    # 起動直後などタイトルがまだ出ていないこともあるので、dev が付けた名前も見る
    case "$wname" in claude*) found=1 ;; esac

    [ "$found" = "1" ] || return
    if [ "$unread" = "1" ]; then
        printf '!|%s' "$summary"
    else
        printf '.|%s' "$summary"
    fi
}

# セッションのアクティブペインで動いているコマンド名
# シェルのまま（空のターミナル）なら dev が付けた名前を返す
win_command() {
    local wid="$1" wname="$2" cmd
    cmd="$(printf '%s\n' "$DATA" | awk -F'|' -v w="$wid" '$2 == w && $6 != "1" && $7 == "1" { print $5; exit }')"
    case "$cmd" in
        '' | sh | bash | zsh | fish | login) printf '%s' "$wname" ;;
        *) printf '%s' "$cmd" ;;
    esac
}

render() {
    local cur_session cur_window width height
    IFS='|' read -r cur_session cur_window width height < <(
        tmux display-message -p -t "$TMUX_PANE" \
            '#{session_name}|#{window_id}|#{pane_width}|#{pane_height}' 2>/dev/null
    )
    [ -n "$cur_window" ] || return 1
    case "$width" in '' | *[!0-9]*) width=36 ;; esac
    case "$height" in '' | *[!0-9]*) height=40 ;; esac

    local buf="" rows="" row=0
    local si=0 wi sname wid wname info state summary label head avail mark right pad

    while IFS= read -r sname; do
        [ -n "$sname" ] || continue
        si=$((si + 1))

        if [ "$sname" = "$cur_session" ]; then
            buf="${buf}${C_FOLDER_CUR} ${si} $(trunc "$sname" $((width - 4)))${C_RESET}"$'\n'
        else
            buf="${buf}${C_FOLDER} ${si}${C_RESET}${C_DIM} $(trunc "$sname" $((width - 4)))${C_RESET}"$'\n'
        fi
        rows="${rows}${row}|s|${sname}"$'\n'
        row=$((row + 1))

        wi=0
        while IFS='|' read -r wid wname; do
            [ -n "$wid" ] || continue
            wi=$((wi + 1))

            info="$(win_claude "$wid" "$wname")"
            state="${info%%|*}"
            summary=""
            case "$info" in *'|'*) summary="${info#*|}" ;; esac

            case "$state" in
                '!') right="${C_UNREAD}●${C_RESET}" ; mark=1 ;;
                '.') right="${C_IDLE}○${C_RESET}"   ; mark=1 ;;
                *)   right=""                       ; mark=0 ;;
            esac

            # 名前より中身が分かるものを出す:
            # Claude は作業概要、それ以外のセッションは動いているコマンド名
            if [ -n "$summary" ]; then
                wname="$summary"
            elif [ -z "$state" ]; then
                wname="$(win_command "$wid" "$wname")"
            fi

            if [ "$wid" = "$cur_window" ]; then
                head="  >${wi} "
            else
                head="   ${wi} "
            fi
            # 末尾は 1 列空けてインジケーターを置くので、名前に使えるのはその手前まで
            avail=$(( width - ${#head} - mark - 2 ))
            label="${head}$(trunc "$wname" "$avail")"

            pad=$(( width - $(str_width "$label") - mark - 1 ))
            [ "$pad" -lt 1 ] && pad=1

            if [ "$wid" = "$cur_window" ]; then
                buf="${buf}${C_WIN_CUR}${label}$(printf "%${pad}s" '')${C_RESET}${right}"$'\n'
            elif [ "$sname" = "$cur_session" ]; then
                buf="${buf}${label}${C_RESET}$(printf "%${pad}s" '')${right}"$'\n'
            else
                buf="${buf}${C_DIM}${label}${C_RESET}$(printf "%${pad}s" '')${right}"$'\n'
            fi

            rows="${rows}${row}|w|${wid}"$'\n'
            row=$((row + 1))
        done < <(printf '%s\n' "$DATA" | awk -F'|' -v s="$sname" '$1 == s && $6 != "1" { print $2"|"$3 }' | awk '!seen[$0]++')

        buf="${buf}"$'\n'
        row=$((row + 1))
    done < <(printf '%s\n' "$DATA" | cut -d'|' -f1 | awk 'NF && !seen[$0]++')

    printf '%s' "$rows" > "${ROWS_FILE}.$$" 2>/dev/null && mv -f "${ROWS_FILE}.$$" "$ROWS_FILE" 2>/dev/null

    # フッタ（キーヒント）は下端に固定する。本文と重なる高さしかないときは出さない
    local footer="" footer_rows=4
    if [ "$row" -lt $((height - footer_rows)) ]; then
        footer="${C_HINT}$(printf '%*s' "$width" '' | tr ' ' '-')${C_RESET}"$'\n'
        footer="${footer}${C_HINT} 1-9 folder / then N win${C_RESET}"$'\n'
        footer="${footer}${C_HINT} c claude  t term  g lg${C_RESET}"$'\n'
        footer="${footer}${C_HINT} e editor  o open  x kill${C_RESET}"
        buf="${buf}${ESC}[$((height - footer_rows + 1));1H${footer}"
    fi

    printf '%s' "$buf"
}

last=""
while :; do
    if [ "$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)" = "1" ]; then
        DATA="$(tmux list-panes -a -F \
            '#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{@sidebar}|#{pane_active}|#{pane_title}' 2>/dev/null)"
        out="$(render)"
        if [ -n "$out" ] && [ "$out" != "$last" ]; then
            printf '%s[H%s[2J%s' "$ESC" "$ESC" "$out"
            last="$out"
        fi
        needs_render=0
        read -t 1 -n 1 _discard 2>/dev/null
    else
        # 画面に出ていないので描画しない。次にアクティブになったとき必ず描き直す
        last=""
        read -t 2 -n 1 _discard 2>/dev/null
    fi
done
