#!/bin/bash

# dev ピッカー
#
# prefix + Space から tmux display-popup 越しに呼ばれ、開いているウィンドウを
# パスでグルーピングして fzf に出す。常駐サイドバーの代わりに「押したときだけ」
# 一覧を出すのが役割で、グルーピング・未読マーク・git 状態はここに集約している。
#
#   tmux-picker.sh        fzf を出し、選ばれたウィンドウへ移動する
#   tmux-picker.sh list   fzf に流す行だけを出す（ctrl-x で閉じたあとの再読み込み用）
#
# 出力は「<window_id> TAB <パス> TAB <表示>」。fzf には 3 列目だけ見せ、
# 1 列目で select-window、2 列目で git のプレビューを引く。
# NO_COLOR が設定されていれば色を付けない（nvim 側の telescope から読むときに使う）。

set -u

GLOBAL_SESSION="${TMUX_DEV_SESSION:-dev}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# Claude Code がペインタイトルの頭に付けるマーク（"✳ 作業概要" の形で出る）
CLAUDE_MARK='✳'
# 作業中でないときのタイトル。これは概要として扱わない
CLAUDE_IDLE='Claude Code'

list() {
    local waiting=" " f cur color=1
    [ -n "${NO_COLOR:-}" ] && color=0

    # 未読フラグの一覧。glob なのでプロセスは起きない
    for f in /tmp/claude-waiting-*; do
        [ -e "$f" ] || continue
        waiting="${waiting}${f#/tmp/claude-waiting-} "
    done

    cur="$(tmux display-message -p -t "=$GLOBAL_SESSION:" '#{window_id}' 2>/dev/null)"

    tmux list-panes -s -t "=$GLOBAL_SESSION" -F \
        '#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{pane_active}|#{pane_current_path}|#{pane_title}' 2>/dev/null \
    | awk -F'|' -v mark="$CLAUDE_MARK" -v idle="$CLAUDE_IDLE" -v waiting="$waiting" -v cur="$cur" '
    # ペイン一覧をウィンドウごとの 1 行にまとめ、パスの表示名まで決める。
    # 出力: <パス> \t <出現順> \t <window_id> \t <state> \t <グループ名> \t <ラベル> \t <現在なら1>
    #   state: ! = 未読、. = 動作中、空 = Claude なし
    BEGIN { shell = "^(sh|bash|zsh|fish|login)$"; OFS = "\t" }
    {
        title = $7
        for (i = 8; i <= NF; i++) title = title "|" $i   # タイトルに | が入っても拾えるように

        wid = $1
        if (!(wid in seen)) {
            seen[wid] = 1
            order[++n] = wid
            wname[wid] = $2
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

        if (dir_fallback[wid] == "") dir_fallback[wid] = $6
        if ($5 == "1") { acmd[wid] = $4; dir_active[wid] = $6 }
    }
    END {
        # パスの表示名は basename。同じ basename が複数あるときだけ親を足して区別する
        for (i = 1; i <= n; i++) {
            wid = order[i]
            d = (dir_active[wid] != "" ? dir_active[wid] : dir_fallback[wid])
            wdir[wid] = d
            if (d in base) continue
            b = d
            sub(".*/", "", b)
            if (b == "") b = d
            base[d] = b
            cnt[b]++
            dirs[++dn] = d
        }
        for (j = 1; j <= dn; j++) {
            d = dirs[j]
            if (cnt[base[d]] < 2) continue
            p = d
            sub("/[^/]*$", "", p)
            sub(".*/", "", p)
            if (p != "") base[d] = p "/" base[d]
        }

        for (i = 1; i <= n; i++) {
            wid = order[i]
            # 起動直後などタイトルがまだ出ていないこともあるので、dev が付けた名前も見る
            if (state[wid] == "" && wname[wid] ~ /^claude/ && acmd[wid] != "" && acmd[wid] !~ shell) state[wid] = "."

            if (summary[wid] != "")   label = summary[wid]
            # Claude Code はプロセス名がバージョン番号になるので名前で出す
            else if (state[wid] != "") label = "claude"
            else if (acmd[wid] != "")  label = acmd[wid]
            else                       label = wname[wid]

            print wdir[wid], i, wid, state[wid], base[wdir[wid]], label, (wid == cur ? "1" : "0")
        }
    }' \
    | sort -t"$(printf '\t')" -k1,1 -k2,2n \
    | awk -F'\t' -v color="$color" '
    BEGIN {
        if (color == "1") {
            R = "\033[0m"; YEL = "\033[33;1m"; DIM = "\033[2m"
            CYA = "\033[36;1m"; WHT = "\033[37;1m"
        }
    }
    {
        wid = $3; st = $4; grp = $5; label = $6
        if (length(grp) > 18) grp = substr(grp, 1, 17) "~"
        grp = sprintf("%-18s", grp)

        if ($7 == "1") { head = CYA ">" R; grp = CYA grp R }
        else           { head = " ";       grp = WHT grp R }

        if (st == "!")      m = YEL "●" R
        else if (st == ".") m = DIM "○" R
        else                m = " "

        printf "%s\t%s\t%s%s %s %s\n", wid, $1, head, m, grp, label
    }'
}

case "${1:-}" in
    list)
        list
        ;;
    *)
        rows="$(list)"
        if [ -z "$rows" ]; then
            echo "開いているウィンドウがありません（'dev .' で開けます）"
            read -r -t 2 _ 2>/dev/null
            exit 0
        fi

        sel="$(printf '%s\n' "$rows" | fzf \
            --ansi \
            --layout=reverse \
            --cycle \
            --delimiter=$'\t' \
            --with-nth=3 \
            --prompt='dev ❯ ' \
            --header='enter 移動 / ctrl-x 閉じる / esc 中止' \
            --preview='git -C {2} -c color.status=always --no-optional-locks status -sb 2>/dev/null || echo "(git 管理外)"' \
            --preview-window='down,5,border-top' \
            --bind="ctrl-x:execute-silent(tmux kill-window -t {1})+reload($SELF list)")"

        [ -n "$sel" ] || exit 0
        tmux select-window -t "${sel%%$'\t'*}"
        ;;
esac
