#!/bin/bash

# tmux サイドバー: フォルダ(tmuxセッション) → セッション(tmuxウィンドウ) のツリーを左端に常駐表示する
# 各ウィンドウの左端ペインで実行される。表示専用でフォーカスは受け取らない
# （フォーカスが来ても .tmux.conf の after-select-pane フックが隣のペインへ追い出す）
#
# 再描画は 1 秒ポーリング + SIGUSR1。内容が変わらないときは描画しないのでちらつかない。
# 非アクティブなウィンドウのサイドバーは画面に出ていないので描画をスキップする。
#
# 1 描画あたりのプロセス生成は tmux 2 回 + awk 1 回に抑えてある。
# 幅の計算やパディングでコマンド置換を使うと、1 文字ごとに fork が走って
# 描画が数百 ms 単位で重くなるため、これらはグローバル変数で値を返している。
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
trap ':' USR1

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

# 以下 3 つは戻り値をグローバル変数に置く（$() を使うと 1 文字ごとに fork してしまうため）

# 1文字の表示幅 → CHAR_W。ASCII は 1、それ以外は 2
# bash 3.2 の printf は先頭バイトを符号付きで返すので、0-127 の外側を全角として扱う
char_width() {
    printf -v _cw '%d' "'$1" 2>/dev/null
    if [ "${_cw:-0}" -ge 32 ] && [ "${_cw:-0}" -le 126 ]; then
        CHAR_W=1
    else
        CHAR_W=2
    fi
}

# 文字列の表示幅 → STR_W
str_width() {
    local s="$1" i
    STR_W=0
    for (( i = 0; i < ${#s}; i++ )); do
        char_width "${s:i:1}"
        STR_W=$(( STR_W + CHAR_W ))
    done
}

# 表示幅 max に収まるよう切り詰めた文字列 → TRUNC（溢れたら末尾を ~ にする）
trunc() {
    local s="$1" max="$2" i j w=0
    for (( i = 0; i < ${#s}; i++ )); do
        char_width "${s:i:1}"
        if [ $(( w + CHAR_W )) -gt "$max" ]; then
            TRUNC="${s:0:i}"
            # ~ を置くぶんの幅を末尾から削る
            while [ "$w" -ge "$max" ] && [ -n "$TRUNC" ]; do
                j=$(( ${#TRUNC} - 1 ))
                char_width "${TRUNC:j:1}"
                w=$(( w - CHAR_W ))
                TRUNC="${TRUNC:0:j}"
            done
            TRUNC="${TRUNC}~"
            return
        fi
        w=$(( w + CHAR_W ))
    done
    TRUNC="$s"
}

# tmux から取ったペイン一覧を、セッション（ウィンドウ）ごとの 1 行にまとめる
#   出力: <フォルダ名>|<window_id>|<state>|<表示ラベル>
#   state: ! = 未読、. = 動作中/既読、空 = Claude なし
#
# 表示ラベルは「そこで何が動いているか」。ウィンドウ名（claude1, sh1 …）は出さない:
#   Claude Code はペインタイトルの ✳ に続く作業概要、まだ何もしていなければ claude、
#   それ以外はアクティブペインのコマンド名（シェルのままなら zsh）
#
# Claude Code はプロセス名がバージョン番号（例 2.1.238）になるため
# pane_current_command では判別できない。タイトル頭の ✳ で見分ける
summarize() {
    printf '%s\n' "$DATA" | awk -F'|' -v mark="$CLAUDE_MARK" -v idle="$CLAUDE_IDLE" -v waiting="$WAITING" '
    BEGIN { shell = "^(sh|bash|zsh|fish|login)$" }
    $6 == "1" { next }   # サイドバー自身は並べない
    {
        title = $8
        for (i = 9; i <= NF; i++) title = title "|" $i   # タイトルに | が入っても拾えるように

        wid = $2
        if (!(wid in seen)) {
            seen[wid] = 1
            order[++n] = wid
            wsess[wid] = $1
            wname[wid] = $3
            state[wid] = ""
            summary[wid] = ""
            acmd[wid] = ""
        }

        # Claude を抜けたあともペインタイトルの ✳ が残ることがあるので、
        # シェルに戻っているペインは動いていないものとして扱う
        alive = ($5 !~ shell)

        if (alive && index(waiting, " " $4 " ") > 0) state[wid] = "!"

        t = title
        if (alive && sub("^" mark " ", "", t)) {
            if (state[wid] != "!") state[wid] = "."
            if (t != idle && summary[wid] == "") summary[wid] = t
        }

        if ($7 == "1") acmd[wid] = $5
    }
    END {
        for (i = 1; i <= n; i++) {
            wid = order[i]
            # 起動直後などタイトルがまだ出ていないこともあるので、dev が付けた名前も見る
            # （ただしシェルに戻っていれば Claude は終了しているので補わない）
            if (state[wid] == "" && wname[wid] ~ /^claude/ && acmd[wid] != "" && acmd[wid] !~ shell) state[wid] = "."

            if (summary[wid] != "") {
                label = summary[wid]
            } else if (state[wid] != "") {
                # Claude Code はプロセス名がバージョン番号になるので名前で出す
                label = "claude"
            } else if (acmd[wid] != "") {
                label = acmd[wid]
            } else {
                label = wname[wid]
            }
            print wsess[wid] "|" wid "|" state[wid] "|" label
        }
    }'
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

    # 未読フラグの一覧。glob なのでプロセスは起きない
    local f
    WAITING=" "
    for f in /tmp/claude-waiting-*; do
        [ -e "$f" ] || continue
        WAITING="${WAITING}${f#/tmp/claude-waiting-} "
    done

    local buf="" rows="" row=0 si=0 wi=0 prev_sess=""
    local sess wid state label head avail mark right pad pad_str

    while IFS='|' read -r sess wid state label; do
        [ -n "$wid" ] || continue

        if [ "$sess" != "$prev_sess" ]; then
            if [ -n "$prev_sess" ]; then
                buf="${buf}"$'\n'
                row=$(( row + 1 ))
            fi
            prev_sess="$sess"
            si=$(( si + 1 ))
            wi=0

            trunc "$sess" $(( width - 4 ))
            if [ "$sess" = "$cur_session" ]; then
                buf="${buf}${C_FOLDER_CUR} ${si} ${TRUNC}${C_RESET}"$'\n'
            else
                buf="${buf}${C_FOLDER} ${si}${C_RESET}${C_DIM} ${TRUNC}${C_RESET}"$'\n'
            fi
            rows="${rows}${row}|s|${sess}"$'\n'
            row=$(( row + 1 ))
        fi

        wi=$(( wi + 1 ))
        case "$state" in
            '!') right="${C_UNREAD}●${C_RESET}" ; mark=1 ;;
            '.') right="${C_IDLE}○${C_RESET}"   ; mark=1 ;;
            *)   right=""                       ; mark=0 ;;
        esac

        if [ "$wid" = "$cur_window" ]; then
            head="  >${wi} "
        else
            head="   ${wi} "
        fi

        # 末尾は 1 列空けてインジケーターを置くので、名前に使えるのはその手前まで
        avail=$(( width - ${#head} - mark - 2 ))
        trunc "$label" "$avail"
        label="${head}${TRUNC}"

        str_width "$label"
        pad=$(( width - STR_W - mark - 1 ))
        [ "$pad" -lt 1 ] && pad=1
        printf -v pad_str "%${pad}s" ''

        if [ "$wid" = "$cur_window" ]; then
            buf="${buf}${C_WIN_CUR}${label}${pad_str}${C_RESET}${right}"$'\n'
        elif [ "$sess" = "$cur_session" ]; then
            buf="${buf}${label}${C_RESET}${pad_str}${right}"$'\n'
        else
            buf="${buf}${C_DIM}${label}${C_RESET}${pad_str}${right}"$'\n'
        fi

        rows="${rows}${row}|w|${wid}"$'\n'
        row=$(( row + 1 ))
    done < <(summarize)

    printf '%s' "$rows" > "${ROWS_FILE}.$$" 2>/dev/null && mv -f "${ROWS_FILE}.$$" "$ROWS_FILE" 2>/dev/null

    # フッタ（キーヒント）は下端に固定する。本文と重なる高さしかないときは出さない
    local footer_rows=4 sep
    if [ "$row" -lt $(( height - footer_rows )) ]; then
        printf -v sep "%${width}s" ''
        sep="${sep// /-}"
        buf="${buf}${ESC}[$(( height - footer_rows + 1 ));1H${C_HINT}${sep}${C_RESET}"$'\n'
        buf="${buf}${C_HINT} 1-9 folder / then N win${C_RESET}"$'\n'
        buf="${buf}${C_HINT} c claude  t term  g lg${C_RESET}"$'\n'
        buf="${buf}${C_HINT} e editor  o open  x kill${C_RESET}"
    fi

    RENDERED="$buf"
}

last=""
while :; do
    if [ "$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)" = "1" ]; then
        DATA="$(tmux list-panes -a -F \
            '#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{@sidebar}|#{pane_active}|#{pane_title}' 2>/dev/null)"
        RENDERED=""
        render
        if [ -n "$RENDERED" ] && [ "$RENDERED" != "$last" ]; then
            printf '%s[H%s[2J%s' "$ESC" "$ESC" "$RENDERED"
            last="$RENDERED"
        fi
        read -t 1 -n 1 _discard 2>/dev/null
    else
        # 画面に出ていないので描画しない。次にアクティブになったとき必ず描き直す
        last=""
        read -t 2 -n 1 _discard 2>/dev/null
    fi
done
