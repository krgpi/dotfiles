---
name: fix-gh-ci-error
description: GitHub PRのCI失敗を調査して修正する
argument-hint: "[PR番号(省略時は現在のブランチのPR)]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

`$ARGUMENTS` でPR番号が指定されていれば `gh pr view $ARGUMENTS`、なければ `gh pr view` で現在のブランチのPRを対象にする。

1. `gh pr checks` で失敗チェックを特定し、`gh run view <run-id> --log-failed` でエラーログを取得する
2. 原因を分析してコードを修正する。可能ならローカルで同じチェックを実行して検証する
3. 失敗チェック名・原因・修正内容を報告し、コミットするか確認する
