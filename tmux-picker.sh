#!/bin/bash

# dev ピッカー
#
# prefix + Space（または prefix なしの Alt-Space）から tmux new-window 越しに呼ばれ、開いているウィンドウを
# パスでグルーピングして fzf に出す。常駐サイドバーの代わりに「押したときだけ」
# 一覧を出すのが役割で、グルーピング・未読マーク・git 状態はここに集約している。
# display-popup ではなく new-window なのは、iTerm2 の tmux -CC 統合が popup の
# レンダリングに対応していないため（tmux-dev.sh の TMUX_ATTACH_FLAGS 参照）。
# コマンド終了と同時にこのウィンドウ自体が自動で閉じ、直前のウィンドウへ戻る
#
#   tmux-picker.sh              fzf を出し、選ばれたウィンドウへ移動する
#   tmux-picker.sh list         fzf に流す行だけを出す（x で閉じたあとの再読み込み用）
#
# 環境変数 TMUX_PICKER_ORIGIN には呼び出し元（ピッカーを開く前にいた）ウィンドウの
# window_id が入る（.tmux.conf 側で new-window -e により #{window_id} を渡す）。
# ピッカー自身のウィンドウは一覧から除外し、この呼び出し元ウィンドウを
# 「現在地」として扱う
#
# fzf は vim 風に使う。入力欄は隠しておき j / k で移動、enter か space で開く。
# / で入力欄を出して絞り込む（その間 j / k / space / t / x は検索文字に戻る）。
# 絞り込み中の esc は入力欄を畳んで全件に戻し、通常時の esc は中止。
# ウィンドウ自体がフォーカスを持つので t / x に ctrl は要らない。
# t は選択行と同じパスに新しいターミナルを開いてそこへ移動する。
#
# 出力は「<window_id> TAB <パス> TAB <表示>」。fzf には 3 列目だけ見せ、
# 1 列目で select-window、2 列目で git のプレビューと t のパスを引く。
# NO_COLOR が設定されていれば色を付けない（nvim 側の telescope から読むときに使う）。

set -u

GLOBAL_SESSION="${TMUX_DEV_SESSION:-dev}"
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$DOTFILES_DIR/$(basename "$0")"
DEV="$DOTFILES_DIR/tmux-dev.sh"
ORIGIN_WID="${TMUX_PICKER_ORIGIN:-}"

# Claude Code がペインタイトルの頭に付けるマーク（"✳ 作業概要" の形で出る）
CLAUDE_MARK='✳'
# 作業中でないときのタイトル。これは概要として扱わない
CLAUDE_IDLE='Claude Code'
# Codex CLI はプロセス名がそのまま "codex" になる（Claude と違いバージョン番号化しない）
CODEX_CMD='^codex$'

# ウィンドウごとのデータを集める共通部分。出力: <パス> \t <window_id> \t <state> \t
# <グループ名> \t <ラベル> \t <現在なら1> \t <ブランチ名> \t <staged:1|空> \t
# <unstaged:1|空> \t <ahead数|空> \t <behind数|空>（state は list() 冒頭のコメント参照）
collect_rows() {
    local waiting=" " running=" " f cur

    # 未読・実行中フラグの一覧。glob なのでプロセスは起きない
    for f in /tmp/claude-waiting-*; do
        [ -e "$f" ] || continue
        waiting="${waiting}${f#/tmp/claude-waiting-} "
    done
    for f in /tmp/claude-running-*; do
        [ -e "$f" ] || continue
        running="${running}${f#/tmp/claude-running-} "
    done

    self_wid="$(tmux display-message -p -t "=$GLOBAL_SESSION:" '#{window_id}' 2>/dev/null)"
    cur="${ORIGIN_WID:-$self_wid}"

    tmux list-panes -s -t "=$GLOBAL_SESSION" -F \
        '#{window_id}|#{window_name}|#{pane_id}|#{pane_current_command}|#{pane_active}|#{pane_current_path}|#{pane_title}' 2>/dev/null \
    | awk -F'|' -v mark="$CLAUDE_MARK" -v idle="$CLAUDE_IDLE" -v codex_cmd="$CODEX_CMD" -v waiting="$waiting" -v running="$running" -v cur="$cur" -v self="$self_wid" '
    # ペイン一覧をウィンドウごとの 1 行にまとめ、パスの表示名まで決める。
    # 出力: <パス> \t <出現順> \t <window_id> \t <state> \t <グループ名> \t <ラベル> \t <現在なら1>
    #   state: ! = 未読、+ = 実行中、. = 起動中（入力待ち）、c = Codex、空 = 何もなし
    BEGIN { shell = "^(sh|bash|zsh|fish|login)$"; OFS = "\t" }
    $1 == self { next }  # ピッカー自身の一時ウィンドウは一覧に出さない
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
        else if (alive && index(running, " " $3 " ") > 0 && state[wid] != "!") state[wid] = "+"

        t = title
        if (alive && sub("^" mark " ", "", t)) {
            if (state[wid] == "") state[wid] = "."
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
            # Codex には未読・実行中フックが無いので、プロセス名だけで動作中とみなす
            if (state[wid] == "" && acmd[wid] ~ codex_cmd) state[wid] = "c"

            if (summary[wid] != "")    label = summary[wid]
            else if (state[wid] == "c") label = "codex"
            # Claude Code はプロセス名がバージョン番号になるので名前で出す
            else if (state[wid] != "")  label = "claude"
            else if (acmd[wid] != "")   label = acmd[wid]
            else                        label = wname[wid]

            print wdir[wid], i, wid, state[wid], base[wdir[wid]], label, (wid == cur ? "1" : "0")
        }
    }' \
    | sort -t"$(printf '\t')" -k1,1 -k2,2n \
    | while IFS=$'\t' read -r dir ord wid state grp label cur; do
        if [ "$dir" != "${prev_dir:-}" ]; then
            branch="$(git -C "$dir" branch --show-current 2>/dev/null)"
            staged=""; unstaged=""; ahead=""; behind=""
            if [ -n "$branch" ]; then
                git -C "$dir" diff --cached --quiet 2>/dev/null || staged=1
                git -C "$dir" diff --quiet 2>/dev/null || unstaged=1
                upstream="$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)"
                if [ -n "$upstream" ]; then
                    counts="$(git -C "$dir" rev-list --count --left-right "$upstream...HEAD" 2>/dev/null)"
                    behind="${counts%%$'\t'*}"; [ "$behind" = "0" ] && behind=""
                    ahead="${counts##*$'\t'}"; [ "$ahead" = "0" ] && ahead=""
                fi
            fi
            prev_dir="$dir"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$dir" "$wid" "$state" "$grp" "$label" "$cur" "$branch" "$staged" "$unstaged" "$ahead" "$behind"
    done
}

# fzf に渡す ANSI 色付きの一覧。NO_COLOR が設定されていれば色を付けない
list() {
    local color=1
    [ -n "${NO_COLOR:-}" ] && color=0

    collect_rows | awk -F'\t' -v color="$color" '
    BEGIN {
        BRANCH_NAME_W = 12
        BRANCH_W = 20
        if (color == "1") {
            R = "\033[0m"; YEL = "\033[33;1m"; DIM = "\033[2m"; BLINK = "\033[5m"
            CYA = "\033[36;1m"; WHT = "\033[37;1m"; MAG = "\033[35;1m"; GRN = "\033[32;1m"; RED = "\033[31;1m"
        }
    }
    {
        wid = $2; st = $3; grp = $4; label = $5
        branch = $7; staged = $8; unstaged = $9; ahead = $10; behind = $11
        if (length(grp) > 18) grp = substr(grp, 1, 17) "~"
        grp = sprintf("%-18s", grp)

        if ($6 == "1") { head = CYA ">" R; grp = CYA grp R }
        else           { head = " ";       grp = WHT grp R }

        if (st == "!")      m = YEL "●" R
        else if (st == "+") m = BLINK "○" R
        else if (st == ".") m = DIM "○" R
        else if (st == "c") m = MAG "◆" R
        else                m = " "

        # ブランチ列: 緑の名前 + 黄(staged)/赤(unstaged) + マゼンタの ahead/behind。
        # ⇡/⇣ は UTF-8 3バイトだが awk の length() はバイト単位なので、
        # パッド幅は文字ではなく見た目の桁数を自前で積み上げて計算する。
        # 名前自体は固定幅に切り詰めて、この列の幅が常に揃うようにする
        if (length(branch) > BRANCH_NAME_W) branch = substr(branch, 1, BRANCH_NAME_W - 1) "~"
        vis = length(branch)
        b = GRN branch R
        if (staged == "1")   { b = b YEL "+" R; vis++ }
        if (unstaged == "1") { b = b RED "*" R; vis++ }
        if (ahead != "")     { b = b MAG "⇡" ahead R; vis += 1 + length(ahead) }
        if (behind != "")    { b = b MAG "⇣" behind R; vis += 1 + length(behind) }
        if (branch != "" && vis < BRANCH_W) b = b sprintf("%*s", BRANCH_W - vis, "")
        else if (branch == "") b = sprintf("%*s", BRANCH_W, "")

        printf "%s\t%s\t%s%s %s %s %s\n", wid, $1, head, m, grp, b, label
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
            --no-input \
            --delimiter=$'\t' \
            --with-nth=3 \
            --prompt='/ ' \
            --header='j/k 移動  / 検索  enter/space 開く  t 新しいターミナル  x 閉じる  esc 中止' \
            --preview='git -C {2} -c color.status=always --no-optional-locks status -sb 2>/dev/null || echo "(git 管理外)"' \
            --preview-window='down,5,border-top' \
            --bind='j:down,k:up,space:accept' \
            --bind='/:show-input+clear-query+unbind(j,k,space,t,x)' \
            --bind='esc:transform:[ "$FZF_INPUT_STATE" = enabled ] && echo "rebind(j,k,space,t,x)+hide-input+search()" || echo abort' \
            --bind="t:execute-silent($DEV new term {2})+abort" \
            --bind="x:execute-silent(tmux kill-window -t {1})+reload($SELF list)")"

        [ -n "$sel" ] || exit 0
        tmux select-window -t "${sel%%$'\t'*}"
        ;;
esac
