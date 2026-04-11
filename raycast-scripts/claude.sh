#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Claude
# @raycast.mode fullOutput
# @raycast.icon 💬
# @raycast.description Claude

# Optional parameters:
# @raycast.argument1 { "type": "text", "placeholder": "Question" }

# claudeはRaycastのデフォルトPATHに含まれないため追加（~/.local/bin）
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

original=$(pbpaste)
intent="$1"

if [ -z "$original" ]; then
  echo "クリップボードが空です"
  exit 1
fi

if [ -z "$intent" ]; then
  echo "入力してください"
  exit 1
fi

system=""

user_message="【受け取ったメッセージ】
${original}

【返信したい内容】
${intent}"

result=$(echo "$user_message" | claude -p --system-prompt "$system" --model haiku 2>&1)

if [ -z "$result" ]; then
  echo "生成に失敗しました"
  exit 1
fi

echo "$result" | pbcopy
echo "$result"
