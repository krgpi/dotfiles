#!/bin/zsh

# launchd の PATH は /usr/bin:/bin 程度しかないため明示する
export PATH="/opt/homebrew/bin:/Applications/Orca.app/Contents/Resources/bin:/usr/bin:/bin:/usr/sbin:/sbin"

STATE_DIR="$HOME/.cache/gh-review-checkout"
SEEN="$STATE_DIR/seen"
LOG="$STATE_DIR/log"

mkdir -p "$STATE_DIR"
touch "$SEEN"

if [[ -f "$LOG" ]] && (( $(wc -l < "$LOG") > 500 )); then
    tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
exec >> "$LOG" 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

source "$HOME/Developer/dotfiles/zsh/gh.zsh"

prs=$(command gh search prs --review-requested=@me --state=open --json url,repository --jq '.[] | "\(.repository.name) \(.url)"') || exit 1

for line in "${(@f)prs}"; do
    [[ -z "$line" ]] && continue
    repo=${line%% *}
    url=${line#* }
    grep -qFx "$url" "$SEEN" && continue
    dir="$HOME/Developer/$repo"
    if [[ ! -d "$dir/.git" ]]; then
        echo "skip (no clone): $url"
        continue
    fi
    if (builtin cd "$dir" && gh co "$url" < /dev/null); then
        echo "$url" >> "$SEEN"
    else
        echo "failed: $url"
    fi
done
