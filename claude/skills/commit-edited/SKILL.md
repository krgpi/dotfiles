---
name: commit-edited
description: このチャットで編集したファイルだけをステージしてコミットする
disable-model-invocation: true
allowed-tools: Bash, Read
---

このチャットセッション内で自分（Claude）が編集・作成したファイルだけを `git add` してコミットする。触っていないファイルはステージしない。

## 排他制御

他の Claude Code インスタンスとの Git 操作競合を防ぐため、**コミット手順の前に**必ずロックを取得し、**完了後（成功・失敗問わず）**必ず解放する。

### ロック取得

```bash
LOCK_DIR="/tmp/claude-commit-$(git rev-parse --show-toplevel | md5sum | cut -c1-8).lock"
for i in $(seq 1 12); do
  mkdir "$LOCK_DIR" 2>/dev/null && echo "ACQUIRED" && break
  echo "Waiting for lock... ($i/12)"
  sleep 5
done
if [ ! -d "$LOCK_DIR" ]; then
  if find "$LOCK_DIR" -maxdepth 0 -mmin +5 2>/dev/null | grep -q .; then
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" 2>/dev/null && echo "ACQUIRED (stale lock cleared)"
  fi
fi
[ -d "$LOCK_DIR" ] && echo "OK" || echo "FAILED to acquire lock"
```

- `ACQUIRED` または `OK` が出たら次の手順へ進む
- `FAILED` の場合はユーザーに報告して中断する

### ロック解放

Git 操作がすべて完了したら（成功・エラー問わず）、必ず以下を実行する:

```bash
rmdir "/tmp/claude-commit-$(git rev-parse --show-toplevel | md5sum | cut -c1-8).lock" 2>/dev/null
```

## コミット手順

- Conventional Commits 形式でコミットメッセージを自動生成する
- 完了後、コミットしたファイル一覧とメッセージを報告する
