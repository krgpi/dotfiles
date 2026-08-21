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
printf '%s[?1000l%s[?1002l%s[?1003l%s[?1006l' "$ESC" "$ESC" "$ESC" "$ESC"  # マウスレポート無効

trap 'printf "%s[?25h" "$ESC"' EXIT

# 文字列を指定幅に切り詰める
trunc() {
    local s="$1" n="$2"
    if [ "${#s}" -gt "$n" ]; then
        printf '%s~' "${s:0:$((n - 1))}"
    else
        printf '%s' "$s"
    fi
}

# ウィンドウ内の Claude ペインの状態を返す（! =未読, . =動作中/既読, 空=Claudeなし）
win_state() {
    local wid="$1" pid state=""
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        if [ -f "/tmp/claude-waiting-${pid}" ]; then
            printf '!'
            return
        fi
        state="."
    done < <(printf '%s\n' "$DATA" | awk -F'|' -v w="$wid" '$2 == w && $5 == "claude" { print $4 }')
    printf '%s' "$state"
}

render() {
    local cur_session cur_window width height
    IFS='|' read -r cur_session cur_window width height < <(
        tmux display-message -p -t "$TMUX_PANE" \
            '#{session_name}|#{window_id}|#{pane_width}|#{pane_height}' 2>/dev/null
    )
    [ -n "$cur_window" ] || return 1
    case "$width" in '' | *[!0-9]*) width=28 ;; esac
    case "$height" in '' | *[!0-9]*) height=40 ;; esac

    local buf="" rows="" row=0
    local si=0 wi sname wid wname state mark label right pad line

    while IFS= read -r sname; do
        [ -n "$sname" ] || continue
        si=$((si + 1))

        label=" ${si} $(trunc "$sname" $((width - 4)))"
        if [ "$sname" = "$cur_session" ]; then
            buf="${buf}${C_FOLDER_CUR}${label}${C_RESET}"$'\n'
        else
            buf="${buf}${C_FOLDER} ${si}${C_RESET}${C_DIM} $(trunc "$sname" $((width - 4)))${C_RESET}"$'\n'
        fi
        rows="${rows}${row}|s|${sname}"$'\n'
        row=$((row + 1))

        wi=0
        while IFS='|' read -r wid wname; do
            [ -n "$wid" ] || continue
            wi=$((wi + 1))
            state="$(win_state "$wid")"

            case "$state" in
                '!') right="${C_UNREAD}●${C_RESET}" ; mark=1 ;;
                '.') right="${C_IDLE}○${C_RESET}"   ; mark=1 ;;
                *)   right=""                       ; mark=0 ;;
            esac

            if [ "$wid" = "$cur_window" ]; then
                label="  >${wi} $(trunc "$wname" $((width - 7)))"
            else
                label="   ${wi} $(trunc "$wname" $((width - 7)))"
            fi

            pad=$((width - ${#label} - mark - 1))
            [ "$pad" -lt 1 ] && pad=1
            line="${label}$(printf "%${pad}s" '')${right}"

            if [ "$wid" = "$cur_window" ]; then
                buf="${buf}${C_WIN_CUR}${label}$(printf "%${pad}s" '')${C_RESET}${right}"$'\n'
            elif [ "$sname" = "$cur_session" ]; then
                buf="${buf}${line}${C_RESET}"$'\n'
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
            '#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{@sidebar}' 2>/dev/null)"
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
