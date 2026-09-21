---
name: commit-edited
description: このチャットで編集したファイルだけをステージしてコミットする。ユーザーが「編集分をコミットして」等と依頼したときに使う。
metadata:
  short-description: このチャットの編集分だけをコミットする
---

# commit-edited

このチャットセッション内で自分が編集・作成したファイルだけを `git add` してコミットする。触っていないファイルはステージしない。

## 排他制御

他の Codex インスタンスとの Git 操作競合を防ぐため、コミット手順の前に必ずロックを取得し、完了後（成功・失敗を問わず）必ず解放する。

### ロック取得

```sh
LOCK_DIR="/tmp/codex/commit$(pwd -P | tr '/' '-').lock"
mkdir -p "$(dirname "$LOCK_DIR")"
ACQUIRED=""
for i in $(seq 1 12); do
  mkdir "$LOCK_DIR" 2>/dev/null && ACQUIRED=1 && break
  if find "$LOCK_DIR" -maxdepth 0 -mmin +5 2>/dev/null | grep -q .; then
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null && ACQUIRED=1 && echo "stale lock cleared" && break
  fi
  echo "Waiting for lock... ($i/12)"
  sleep 5
done
[ -n "$ACQUIRED" ] && echo "OK" || echo "FAILED to acquire lock"
```

- `OK` が出たら次の手順へ進む。
- `FAILED` の場合はユーザーに報告して中断する。

### ロック解放

Git 操作がすべて完了したら（成功・エラーを問わず）、必ず以下を実行する。

```sh
rmdir "/tmp/codex/commit$(pwd -P | tr '/' '-').lock" 2>/dev/null
```

## コミット手順

- このチャットで編集・作成したファイルを明示的に指定してステージする。未関連の既存変更はステージしない。
- Conventional Commits 形式でコミットメッセージを自動生成する。
- 完了後、コミットしたファイル一覧とメッセージを報告する。
