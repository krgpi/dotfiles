---
name: commit-edited
description: このチャットで編集したファイルだけをステージしてコミットする
disable-model-invocation: true
allowed-tools: Bash, Read
---

このチャットセッション内で自分（Claude）が編集・作成したファイルだけを `git add` してコミットする。触っていないファイルはステージしない。

- Conventional Commits 形式でコミットメッセージを自動生成する
- 完了後、コミットしたファイル一覧とメッセージを報告する
