#!/bin/bash
# lazygit用: Claude CLIでコミットメッセージ候補を生成する

diff=$(git diff --cached)
if [ -z "$diff" ]; then
  echo "ステージされた変更がありません"
  exit 1
fi

claude -p --model haiku --effort low "以下のgit diffからコミットメッセージの候補を3つ生成してください。
各候補は1行で、Conventional Commits形式（feat:, fix:, refactor:, docs:, chore: など）で書いてください。
説明や番号は不要で、コミットメッセージだけを1行ずつ出力してください。

$diff" | sed '/^$/d'
