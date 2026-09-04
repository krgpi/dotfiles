#!/bin/bash

# 未読（Claude が入力待ち）のフォルダ名をステータスバー用に 1 行で出す
# status-right から #() で呼ばれる
#
# 常駐サイドバーを畳んだので「気づく」役はここが担う。
# 「切り替える」ほうは prefix + Space のピッカー（tmux-picker.sh）が担当する。
# 未読が無ければ何も出さない（ステータスの右側を占有しない）。

GLOBAL_SESSION="${TMUX_DEV_SESSION:-dev}"

waiting=" "
for f in /tmp/claude-waiting-*; do
    [ -e "$f" ] || continue
    waiting="${waiting}${f#/tmp/claude-waiting-} "
done
[ "$waiting" = " " ] && exit 0

tmux list-panes -s -t "=$GLOBAL_SESSION" -F '#{pane_id}|#{pane_current_path}' 2>/dev/null \
| awk -F'|' -v waiting="$waiting" '
    index(waiting, " " $1 " ") == 0 { next }
    {
        d = $2
        sub(".*/", "", d)
        if (d in seen) next
        seen[d] = 1
        out = out (out == "" ? "" : " ") d
    }
    END { if (out != "") printf "#[fg=yellow,bold]● %s ", out }'
