---
name: fix-gh-ci-error
description: GitHub PRのCI失敗を調査して修正する。PR番号は省略でき、現在のブランチのPRを対象にする。
metadata:
  short-description: GitHub PRのCI失敗を調査・修正する
---

# fix-gh-ci-error

ユーザーが PR 番号を指定していれば `gh pr view <PR番号>`、なければ `gh pr view` で現在のブランチの PR を対象にする。

1. `gh pr checks` で失敗チェックを特定し、`gh run view <run-id> --log-failed` でエラーログを取得する。
2. 原因を分析してコードを修正する。可能ならローカルで同じチェックを実行して検証する。
3. 失敗チェック名・原因・修正内容を報告し、コミットするか確認する。
