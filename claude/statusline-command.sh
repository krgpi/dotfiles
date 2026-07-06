#!/bin/bash
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

now=$(date +%s)

fmt_remaining() {
    local resets=$1
    local max_unit=$2
    local diff=$(( resets - now ))
    [ "$diff" -le 0 ] && echo "0m" && return
    if [ "$max_unit" = "d" ]; then
        local d=$(( diff / 86400 ))
        local h=$(( (diff % 86400) / 3600 ))
        [ "$d" -gt 0 ] && echo "${d}d${h}h" || echo "${h}h"
    else
        local h=$(( diff / 3600 ))
        local m=$(( (diff % 3600) / 60 ))
        [ "$h" -gt 0 ] && echo "${h}h${m}m" || echo "${m}m"
    fi
}

out=""

if [ -n "$model" ]; then
    out="\033[36m${model}\033[0m"
fi

if [ -n "$branch" ]; then
    branch_str="\033[34m⎇ ${branch}\033[0m"
    [ -n "$out" ] && out="${out}  ${branch_str}" || out="${branch_str}"
fi

if [ -n "$used_pct" ]; then
    filled=$(awk "BEGIN {f=int($used_pct/10); if(f>10)f=10; print f}")
    empty=$((10 - filled))
    bar=$(awk -v f="$filled" -v e="$empty" 'BEGIN{for(i=0;i<f;i++) printf "█"; for(i=0;i<e;i++) printf "░"}')
    pct_int=$(printf '%.0f' "$used_pct")
    if [ "$pct_int" -ge 80 ]; then
        bar_color="\033[31m"
    elif [ "$pct_int" -ge 50 ]; then
        bar_color="\033[33m"
    else
        bar_color="\033[32m"
    fi
    ctx="${bar_color}[${bar}] ${pct_int}%\033[0m"
    [ -n "$out" ] && out="${out}  ${ctx}" || out="${ctx}"
fi

if [ -n "$effort" ]; then
    effort_str="\033[33m${effort}\033[0m"
    [ -n "$out" ] && out="${out}  ${effort_str}" || out="${effort_str}"
fi

rate=""
if [ -n "$five_pct" ]; then
    five_rem=""
    [ -n "$five_resets" ] && five_rem="(残$(fmt_remaining "$five_resets" "h"))"
    rate="5h:$(printf '%.0f' "$five_pct")%${five_rem}"
fi
if [ -n "$seven_pct" ]; then
    seven_rem=""
    [ -n "$seven_resets" ] && seven_rem="(残$(fmt_remaining "$seven_resets" "d"))"
    [ -n "$rate" ] && rate="${rate} "
    rate="${rate}7d:$(printf '%.0f' "$seven_pct")%${seven_rem}"
fi
if [ -n "$rate" ]; then
    rate_str="\033[35m${rate}\033[0m"
    [ -n "$out" ] && out="${out}  ${rate_str}" || out="${rate_str}"
fi

printf '%b\n' "${out}"
