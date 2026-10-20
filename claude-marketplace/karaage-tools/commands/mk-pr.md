---
description: "PRを作成する。"
argument-hint: "<ベースブランチ名（デフォルト: main）>"
---

# mk-pr

HEAD to ${1:-main} のドラフトPRを作成する。

PRテンプレート（例: .github/pull_request_template.md）が存在する場合、それに準拠したうえで下記を実施する。

- チェックボックス（`- [ ]`）が存在する場合、下記を実施する。
  - そもそも該当しない場合、取り消し線。（`~~`）
  - 満たしていない場合、そのまま。（`- [ ]`）
  - 満たしている場合、チェック。（`- [x]`）

PRテンプレートが存在しない場合、下記を基本構成とする。該当しないセクションは省略する。

- 概要
- 変更内容
- 関連資料
- 動作確認

各セクションは下記に従う。

- 簡潔に書く。
- 変更内容は「何を可能にするために、何を実装したか」が分かる文章にする。
- 動作確認は、コマンド・アクセス先・操作手順・期待結果まで具体的に書く。実施していない確認を実施済みとして書かない。
- ADR・Design Doc・Issueなど根拠資料があれば関連資料にリンクする。
- PR作成直前のdiffとコミットに合わせ、古い構成の説明を残さない。
- 画像・動画を添付するときは `gh pr create` の `--attach` を使う（[Attaching files with GitHub CLI](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)）。本文中にローカルパスで `![代替テキスト](path/to/image.png)` と書き、同じパスを `--attach` に渡すと、アップロード先のURLに置き換わる。

HEADのブランチがリモートに未プッシュの場合、プッシュの前にローカルブランチ名を変更内容に合った名前へ変える。

- 命名規則は、リポジトリ内の指示（AGENTS.md・CLAUDE.md・CONTRIBUTING.mdなど）を優先する。
- 指示がなければ、リモートにある既存ブランチの命名パターン（prefix・区切り文字・Issue番号の有無など）に倣う。
- 現在の名前がすでに規則に沿っていれば変えない。

---

下記でリモートの既存ブランチを確認できる。

```sh
git branch -r --sort=-committerdate
```

下記でローカルブランチ名を変更できる。

```sh
git branch -m <新しいブランチ名>
```

下記でコミットログを確認できる。

```sh
git log <ベースブランチ名>..HEAD
```

下記でコード差分を確認できる。

```sh
git diff <ベースブランチ名>..HEAD
```

下記でドラフトPRを作成できる。

```sh
gh pr create -d -a @me -B <ベースブランチ名> -t <PRタイトル> -b <PR本文>
```

下記で画像付きのドラフトPRを作成できる。`--attach` は複数回指定できる。

```sh
gh pr create -d -a @me -B <ベースブランチ名> -t <PRタイトル> --body-file <PR本文ファイル> --attach <画像パス>
```
