#!/bin/bash

# 日次の自動アップデート（brew と zshプラグインリポジトリの git pull）
# .zshrc から zsh-defer 経由でバックグラウンド実行される
# 結果は summary に書き出し、次回ターミナル起動時に一度だけ表示される
# 手動で即実行したい場合は --force を付ける

CACHE_DIR="$HOME/.cache/dotfiles-update"
STAMP="$CACHE_DIR/last_run"
LOCK="$CACHE_DIR/lock"
LOG="$CACHE_DIR/last.log"
SUMMARY="$CACHE_DIR/summary"
INTERVAL=86400

REPOS=(
    "$HOME/Developer/fzf-tab"
    "$HOME/Developer/zsh-defer"
)

mkdir -p "$CACHE_DIR"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# 手動実行（--force）のときだけ端末にも進捗を出す
say() {
    (( FORCE )) && printf '%s\n' "$1"
    return 0
}

if (( ! FORCE )) && [[ -f "$STAMP" ]]; then
    last_run=$(cat "$STAMP" 2>/dev/null || echo 0)
    (( $(date +%s) - last_run < INTERVAL )) && exit 0
fi

# 複数ターミナルの同時起動による二重実行を防ぐ（mkdir はアトミック）
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

date +%s > "$STAMP"

if [[ -f "$LOG" ]] && (( $(wc -l < "$LOG") > 500 )); then
    tail -n 500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
echo "" >> "$LOG"
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"

parts=()
failed=0

for repo in "${REPOS[@]}"; do
    name="$(basename "$repo")"
    echo "--- git pull $name ---" >> "$LOG"

    if [[ ! -d "$repo/.git" ]]; then
        echo "not a git repository" >> "$LOG"
        parts+=("$name missing")
        failed=1
        continue
    fi

    # ローカル変更があるリポジトリには触らない
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        echo "skipped (dirty working tree)" >> "$LOG"
        parts+=("$name skipped")
        continue
    fi

    before="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
    if git -C "$repo" pull --ff-only >> "$LOG" 2>&1; then
        after="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
        if [[ "$before" != "$after" ]]; then
            count=$(git -C "$repo" rev-list --count "$before..$after" 2>/dev/null)
            git -C "$repo" log --oneline "$before..$after" >> "$LOG" 2>&1
            parts+=("$name +${count}")
            say "  $name: ${count} commits ($(git -C "$repo" log -1 --format=%h "$before") -> $(git -C "$repo" log -1 --format=%h))"
        else
            say "  $name: up to date"
        fi
    else
        parts+=("$name failed")
        failed=1
        say "  $name: FAILED"
    fi
done

if command -v brew >/dev/null 2>&1; then
    say "  brew: updating..."
    echo "--- brew update ---" >> "$LOG"
    brew update >> "$LOG" 2>&1

    before_count=$(brew outdated --formula --quiet 2>/dev/null | grep -c .)
    if (( before_count > 0 )); then
        echo "--- brew upgrade --formula ---" >> "$LOG"
        brew upgrade --formula >> "$LOG" 2>&1
        after_count=$(brew outdated --formula --quiet 2>/dev/null | grep -c .)
        upgraded=$(( before_count - after_count ))
        parts+=("brew ${upgraded} upgraded")
        say "  brew: ${upgraded} formula upgraded"
        if (( after_count > 0 )); then
            parts+=("${after_count} failed")
            failed=1
        fi
    fi

    # cask は起動中のアプリを差し替えるため自動更新せず件数だけ知らせる
    cask_count=$(brew outdated --cask --quiet 2>/dev/null | grep -c .)
    (( cask_count > 0 )) && parts+=("cask ${cask_count} outdated")
    (( cask_count > 0 )) && say "  cask: ${cask_count} outdated (run: brew upgrade --cask)"
fi

if (( ${#parts[@]} == 0 )); then
    echo "nothing to do" >> "$LOG"
    say "everything up to date"
    rm -f "$SUMMARY"
    exit 0
fi

summary_body="$(printf '%s, ' "${parts[@]}")"
summary_body="${summary_body%, }"
echo "summary: $summary_body" >> "$LOG"

if (( failed )); then
    color=31
else
    color=32
fi
printf '\033[%sm󰚰 update: %s\033[0m \033[90m(%s)\033[0m\n' "$color" "$summary_body" "$LOG" > "$SUMMARY"

# 手動実行時はその場で結果を見せる（次回起動時の表示は不要なので消す）
if (( FORCE )); then
    cat "$SUMMARY"
    rm -f "$SUMMARY"
fi
