#!/bin/bash
set -euo pipefail

dotfiles="$HOME/Developer/dotfiles"
src="$dotfiles/claude/settings.json"
dst="${1:-$dotfiles/claude-work/settings.json}"

out="$(jq --slurpfile src "$src" '
  def isorca: any(.hooks[]?; (.command // "") | contains(".orca/agent-hooks"));
  .hooks = (
    ((.hooks // {}) | map_values(map(select(isorca | not)))) as $base
    | reduce ($src[0].hooks // {} | to_entries[]) as $e ($base;
        .[$e.key] = ((.[$e.key] // []) + ($e.value | map(select(isorca)))))
    | with_entries(select(.value | length > 0))
  )
' "$dst")"

if [ "$out" != "$(cat "$dst")" ]; then
  printf '%s\n' "$out" > "$dst"
fi
