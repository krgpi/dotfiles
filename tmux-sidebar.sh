#!/bin/bash

# tmux サイドバー: 全ウィンドウが1つの tmux セッション（GLOBAL_SESSION）に入り、
# 各ウィンドウの「アクティブペインが今いるパス」でグルーピングしたツリーを
# 左端に常駐表示する。「フォルダ」は tmux 上の実体ではなく、この描画時点の
# パスでその場だけグルーピングする表示上の概念（cd すればグループも動く）。
# 各ウィンドウの左端ペインで実行される。表示専用でフォーカスは受け取らない
# （フォーカスが来ても .tmux.conf の after-select-pane フックが隣のペインへ追い出す）
#
# 再描画は 1 秒ポーリング + SIGUSR1。内容が変わらないときは描画しないのでちらつかない。
# 非アクティブなウィンドウのサイドバーは画面に出ていないので描画をスキップする。
# セッションが1つしかないので #{window_active} を満たすウィンドウは常に高々1つ
# ＝同時に「アクティブ」を名乗るサイドバーは tmux サーバー全体で高々1つになる
# （複数セッションが並立していた旧設計では、ここが競合して古い描画が残る原因だった）。
#
# 1 描画あたりのプロセス生成は最小限に抑えてある。
# 幅の計算やパディングでコマンド置換を使うと、1 文字ごとに fork が走って
# 描画が数百 ms 単位で重くなるため、これらはグローバル変数で値を返している。
#
# グループ行の右にはそのパスの git 状態（ブランチと変更ファイル数）を出す。
# git status を定期的に回すことはしない。Claude のステータスや未読が変われば
# 表示が動くので、そのついでに自分のウィンドウが今いるパスのぶんだけ
# バックグラウンドで数え直す。結果はファイルに置き、描画側は読むだけなので
# git status が遅くてもサイドバーは止まらない。
#
# クリック判定用の行マップ（行番号|種別|対象）を /tmp/tmux-sidebar-rows に書き出す
# （tmux-dev.sh sidebar-click が参照する）

GLOBAL_SESSION="${TMUX_DEV_SESSION:-dev}"
ROWS_FILE="/tmp/tmux-sidebar-rows"

# パスごとの git 状態（"<ブランチ>|<変更ファイル数>"）を 1 ファイルずつ置く
GIT_DIR="/tmp/tmux-sidebar-git"
# 表示が続けて動くあいだ、git status を回す間隔の下限（秒）
GIT_MIN_INTERVAL=3

# Claude Code がペインタイトルの頭に付けるマーク（"✳ 作業概要" の形で出る）
CLAUDE_MARK='✳'
# 作業中でないときのタイトル。これは概要として扱わない
CLAUDE_IDLE='Claude Code'

[ -n "$TMUX_PANE" ] || exit 0

# SIGUSR1 のハンドラは何よりも先に張る
# （既定の動作はプロセス終了なので、起動直後に再描画シグナルが飛んでくると死んでしまう）
# WINCH も拾う。まだ表示していないウィンドウは 80x24 のままなので、初めて開いた
# 瞬間にクライアントの大きさへ伸びる。すぐ描き直さないと増えた行が空で残る
# USR1 は再描画要求でもあるので、git もこのタイミングで数え直す
trap 'GIT_DUE=1' USR1
trap ':' WINCH

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
C_GIT="${ESC}[2;36m"
C_GIT_DIRTY="${ESC}[33m"

# 行頭で出して1行ぶん消す。画面を消してから書くと、その間サイドバーが真っ暗になる
EL="${ESC}[K"

printf '%s]2;sidebar%s\\' "$ESC" "$ESC"   # ペインタイトルを固定
printf '%s[?25l' "$ESC"                    # カーソル非表示
printf '%s[?7l' "$ESC"                     # 行の折り返しを止める（幅の計算がずれても崩さない）
printf '%s[?1000l%s[?1002l%s[?1003l%s[?1006l' "$ESC" "$ESC" "$ESC" "$ESC"  # マウスレポート無効

trap 'printf "%s[?25h%s[?7h" "$ESC" "$ESC"' EXIT

mkdir -p "$GIT_DIR" 2>/dev/null
GIT_DUE=1
GIT_AT=$(( 0 - GIT_MIN_INTERVAL ))
GIT_PID=""
GIT_KEYS=()
GIT_VALS=()
SANI=""

# 以下はいずれも戻り値をグローバル変数に置く（$() を使うと fork してしまうため）

# パス文字列 → ファイル名に使える形（"/" を "_" に）。GIT_DIR のキャッシュキーに使う
sanitize_key() {
    SANI="${1//\//_}"
}

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

# 指定パスの git 状態を数えてキャッシュへ書く（バックグラウンドで呼ぶ）
update_git() {
    local dir="$1" out="$2" line branch="" dirty=0
    while IFS= read -r line; do
        case "$line" in
            '## No commits yet on '*) branch="${line#\#\# No commits yet on }" ;;
            '## '*)
                branch="${line#\#\# }"
                branch="${branch%% *}"
                branch="${branch%%'...'*}"
                ;;
            '') ;;
            *) dirty=$(( dirty + 1 )) ;;
        esac
    done < <(git -C "$dir" --no-optional-locks status --porcelain -b -unormal 2>/dev/null)

    if [ -n "$branch" ]; then
        printf '%s|%s\n' "$branch" "$dirty" > "$out.tmp" 2>/dev/null && mv -f "$out.tmp" "$out" 2>/dev/null
    else
        rm -f "$out" 2>/dev/null
    fi
}

# git を数え直すのは「サイドバーの表示が動いたついで」だけ。
# Claude のステータス（✳ のタイトルや未読）が変われば描画が変わるので、そこに相乗りする。
# 何も起きていないあいだは git status を1回も走らせない
maybe_update_git() {
    [ "$GIT_DUE" = "1" ] || return
    [ "$WIN_ACTIVE" = "1" ] || return
    [ -n "$CUR_DIR" ] && [ -d "$CUR_DIR" ] || return
    # 変化が続いているあいだ毎秒走らせない
    [ $(( SECONDS - GIT_AT )) -ge "$GIT_MIN_INTERVAL" ] || return
    [ -n "$GIT_PID" ] && kill -0 "$GIT_PID" 2>/dev/null && return

    GIT_DUE=0
    GIT_AT=$SECONDS
    sanitize_key "$CUR_DIR"
    # 子で EXIT トラップを外す（親のカーソル復帰がサイドバーへ流れてしまうため）
    ( trap - EXIT; update_git "$CUR_DIR" "$GIT_DIR/$SANI" ) &
    GIT_PID=$!
}

# キャッシュを読み込む（glob と read だけなのでプロセスは起きない）
load_git() {
    local f line
    GIT_KEYS=()
    GIT_VALS=()
    for f in "$GIT_DIR"/*; do
        [ -f "$f" ] || continue
        line=""
        IFS= read -r line < "$f" 2>/dev/null
        [ -n "$line" ] || continue
        GIT_KEYS+=("${f##*/}")
        GIT_VALS+=("$line")
    done
}

# グループ行の右に出す git 表示を組む（グループ名と合わせて表示幅 max に収める）
# $1 はサニタイズ済みのキー（sanitize_key の結果）
#   GIT_PLAIN   幅の計算用
#   GIT_COLORED 実際に出す色付きの文字列
# 幅が足りないときはブランチ名から削る。変更ファイル数は最後まで残す
git_parts() {
    local key="$1" max="$2" i info branch dirty dtext dw bmax
    GIT_PLAIN=""
    GIT_COLORED=""

    info=""
    for (( i = 0; i < ${#GIT_KEYS[@]}; i++ )); do
        [ "${GIT_KEYS[i]}" = "$key" ] || continue
        info="${GIT_VALS[i]}"
        break
    done
    [ -n "$info" ] || return

    branch="${info%%|*}"
    dirty="${info##*|}"
    dtext=""
    case "$dirty" in '' | 0 | *[!0-9]*) ;; *) dtext="*${dirty}" ;; esac
    str_width "$dtext"
    dw=$STR_W

    # グループ名に最低 8 幅は残す
    max=$(( max - 9 ))
    [ "$max" -gt 16 ] && max=16
    [ "$max" -lt "$dw" ] && return

    bmax=$(( max - dw ))
    [ "$dw" -gt 0 ] && bmax=$(( bmax - 1 ))
    if [ "$bmax" -ge 3 ]; then
        trunc "$branch" "$bmax"
        branch="$TRUNC"
    else
        branch=""
    fi

    if [ -n "$branch" ]; then
        GIT_PLAIN="$branch"
        GIT_COLORED="${C_GIT}${branch}${C_RESET}"
    fi
    if [ -n "$dtext" ]; then
        GIT_PLAIN="${GIT_PLAIN:+$GIT_PLAIN }${dtext}"
        GIT_COLORED="${GIT_COLORED:+$GIT_COLORED }${C_GIT_DIRTY}${dtext}${C_RESET}"
    fi
}

# tmux から取ったペイン一覧を、ウィンドウごとの 1 行にまとめる
#   出力: <パス>|<出現順>|<window_id>|<state>|<表示ラベル>（パス→出現順でソート済み）
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
    $5 == "1" { next }   # サイドバー自身は並べない
    {
        title = $8
        for (i = 9; i <= NF; i++) title = title "|" $i   # タイトルに | が入っても拾えるように

        wid = $1
        if (!(wid in seen)) {
            seen[wid] = 1
            order[++n] = wid
            wname[wid] = $2
            state[wid] = ""
            summary[wid] = ""
            acmd[wid] = ""
        }

        # Claude を抜けたあともペインタイトルの ✳ が残ることがあるので、
        # シェルに戻っているペインは動いていないものとして扱う
        alive = ($4 !~ shell)

        if (alive && index(waiting, " " $3 " ") > 0) state[wid] = "!"

        t = title
        if (alive && sub("^" mark " ", "", t)) {
            if (state[wid] != "!") state[wid] = "."
            if (t != idle && summary[wid] == "") summary[wid] = t
        }

        if (dir_fallback[wid] == "") dir_fallback[wid] = $7
        if ($6 == "1") { acmd[wid] = $4; dir_active[wid] = $7 }
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
            d = (dir_active[wid] != "" ? dir_active[wid] : dir_fallback[wid])
            print d "|" i "|" wid "|" state[wid] "|" label
        }
    }' | sort -t'|' -k1,1 -k2,2n
}

# ALL_DIRS[i] のパスに対する表示名を DISP_NAME に置く（ALL_DISP から引く）
disp_for() {
    local target="$1" i
    DISP_NAME="$target"
    for (( i = 0; i < ${#ALL_DIRS[@]}; i++ )); do
        if [ "${ALL_DIRS[i]}" = "$target" ]; then
            DISP_NAME="${ALL_DISP[i]}"
            return
        fi
    done
}

render() {
    local cur_window width height
    IFS='|' read -r cur_window width height WIN_ACTIVE < <(
        tmux display-message -p -t "$TMUX_PANE" \
            '#{window_id}|#{pane_width}|#{pane_height}|#{window_active}' 2>/dev/null
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

    DATA="$(tmux list-panes -s -t "=$GLOBAL_SESSION" -F \
        '#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{@sidebar}|#{pane_active}|#{pane_current_path}|#{pane_title}' 2>/dev/null)"

    local SUMMARY
    SUMMARY="$(summarize)"

    # 今いるウィンドウのパス（グループ判定・git 更新に使う）
    CUR_DIR="$(printf '%s\n' "$DATA" | awk -F'|' -v w="$cur_window" '$1 == w && $6 == "1" { print $7; exit }')"
    [ -n "$CUR_DIR" ] || CUR_DIR="$(printf '%s\n' "$DATA" | awk -F'|' -v w="$cur_window" '$1 == w { print $7; exit }')"

    # 表示中の全パスと、その表示名（basename。重複するものだけ親ディレクトリを足す）
    local d dup existing i j parent base
    ALL_DIRS=()
    while IFS='|' read -r d _; do
        [ -n "$d" ] || continue
        dup=0
        for existing in "${ALL_DIRS[@]}"; do [ "$existing" = "$d" ] && { dup=1; break; }; done
        [ "$dup" = 1 ] || ALL_DIRS+=("$d")
    done <<< "$SUMMARY"

    ALL_DISP=()
    for d in "${ALL_DIRS[@]}"; do
        base="${d##*/}"
        [ -n "$base" ] || base="$d"
        ALL_DISP+=("$base")
    done
    for (( i = 0; i < ${#ALL_DIRS[@]}; i++ )); do
        dup=0
        for (( j = 0; j < ${#ALL_DIRS[@]}; j++ )); do
            [ "$i" = "$j" ] && continue
            [ "${ALL_DISP[i]}" = "${ALL_DISP[j]}" ] && dup=1
        done
        if [ "$dup" = 1 ]; then
            parent="${ALL_DIRS[i]%/*}"
            parent="${parent##*/}"
            [ -n "$parent" ] && ALL_DISP[i]="${parent}/${ALL_DISP[i]}"
        fi
    done

    load_git

    local buf="" rows="" row=0 si=0 wi=0 prev_dir=""
    local dir seq wid state label head avail mark right pad pad_str name gw

    while IFS='|' read -r dir seq wid state label; do
        [ -n "$wid" ] || continue

        if [ "$dir" != "$prev_dir" ]; then
            if [ -n "$prev_dir" ]; then
                buf="${buf}${EL}"$'\n'
                row=$(( row + 1 ))
            fi
            prev_dir="$dir"
            si=$(( si + 1 ))
            wi=0

            disp_for "$dir"
            # グループ行の右端に git（ブランチと変更ファイル数）を右寄せで置く。
            # ウィンドウ行の ○ と列を揃えたいので、こちらは最終列まで使う
            avail=$(( width - ${#si} - 2 ))
            sanitize_key "$dir"
            git_parts "$SANI" "$avail"
            str_width "$GIT_PLAIN"
            gw=$STR_W

            pad_str=""
            if [ "$gw" -gt 0 ]; then
                trunc "$DISP_NAME" $(( avail - gw - 1 ))
                name="$TRUNC"
                str_width "$name"
                pad=$(( avail - STR_W - gw ))
                [ "$pad" -lt 1 ] && pad=1
                printf -v pad_str "%${pad}s" ''
            else
                trunc "$DISP_NAME" $(( avail - 1 ))
                name="$TRUNC"
            fi

            if [ "$dir" = "$CUR_DIR" ]; then
                buf="${buf}${EL}${C_FOLDER_CUR} ${si} ${name}${C_RESET}${pad_str}${GIT_COLORED}"$'\n'
            else
                buf="${buf}${EL}${C_FOLDER} ${si}${C_RESET}${C_DIM} ${name}${C_RESET}${pad_str}${GIT_COLORED}"$'\n'
            fi
            rows="${rows}${row}|s|${dir}"$'\n'
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
            buf="${buf}${EL}${C_WIN_CUR}${label}${pad_str}${C_RESET}${right}"$'\n'
        elif [ "$dir" = "$CUR_DIR" ]; then
            buf="${buf}${EL}${label}${C_RESET}${pad_str}${right}"$'\n'
        else
            buf="${buf}${EL}${C_DIM}${label}${C_RESET}${pad_str}${right}"$'\n'
        fi

        rows="${rows}${row}|w|${wid}"$'\n'
        row=$(( row + 1 ))
    done <<< "$SUMMARY"

    printf '%s' "$rows" > "${ROWS_FILE}.$$" 2>/dev/null && mv -f "${ROWS_FILE}.$$" "$ROWS_FILE" 2>/dev/null

    # 行数が減ったときに下へ残る古い行を消す
    buf="${buf}${ESC}[J"

    # フッタ（キーヒント）は下端に固定する。本文と重なる高さしかないときは出さない
    local footer_rows=4 sep
    if [ "$row" -lt $(( height - footer_rows )) ]; then
        printf -v sep "%${width}s" ''
        sep="${sep// /-}"
        buf="${buf}${ESC}[$(( height - footer_rows + 1 ));1H${EL}${C_HINT}${sep}${C_RESET}"$'\n'
        buf="${buf}${EL}${C_HINT} 1-9 folder / then N win${C_RESET}"$'\n'
        buf="${buf}${EL}${C_HINT} c claude  t term  g lg${C_RESET}"$'\n'
        buf="${buf}${EL}${C_HINT} e editor  x kill${C_RESET}"
    fi

    RENDERED="$buf"
}

last=""
while :; do
    # 画面に出ていないウィンドウでも、まだ何も描いていないうちは描いておく。
    # 空のまま置くと、そのウィンドウを初めて開いた瞬間サイドバーが真っ暗に見える
    if [ -z "$last" ] \
        || [ "$(tmux display-message -p -t "$TMUX_PANE" '#{window_active}' 2>/dev/null)" = "1" ]; then
        RENDERED=""
        render
        if [ -n "$RENDERED" ] && [ "$RENDERED" != "$last" ]; then
            printf '%s[H%s' "$ESC" "$RENDERED"
            last="$RENDERED"
            # 表示が動いた = Claude のステータスなどが変わった。そのついでに git を数え直す
            GIT_DUE=1
        fi
        maybe_update_git
        read -t 1 -n 1 _discard 2>/dev/null
    else
        # 画面に出ていないので描画しない。tmux がペインの内容を持っているので
        # last は捨てず、次にアクティブになったとき変化ぶんだけ書き直す
        read -t 2 -n 1 _discard 2>/dev/null
    fi
done
