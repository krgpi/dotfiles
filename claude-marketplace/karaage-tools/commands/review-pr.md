---
description: "PRを専門エージェント並列でレビューし、確信度タグ付きの指摘をまとめ、GitHubにインラインコメント投稿する。"
argument-hint: "[PR番号 or URL]"
---

# review-pr

PR を複数の専門エージェントで並列レビューし、確信度ラベル（`[must]`/`[should]`/`[imo]`/`[q]`）付きの指摘をまとめ、承認後に GitHub へインラインコメントとして投稿する。

引数「$1」は対象PRの番号またはURL。省略時は現在のブランチに紐づくPRを対象にする。

## 大前提

- **エージェントの主張を鵜呑みにしない。** 特にランタイム安全性に関わる指摘は、実装コード（バリデーション層・呼び出し経路）を自分で読んで裏取りする。複数エージェントの見解が食い違う場合は実装を読んで裁定する。
- **GitHubへのコメント投稿はユーザーの明示的な承認後に行う**（「投稿して」等の明示指示があれば省略可）。

## ワークフロー

### Step 1: PR情報と全文diffの取得

```sh
gh pr view <番号> --json title,body,files,additions,deletions,baseRefName,headRefName
gh pr diff <番号>
```

- PR本文・コミットメッセージから意図と「意図的にスコープ外」とされている事項を把握する。
- 現在のworktreeがPRブランチと一致するか確認する（`git diff <PRブランチ> -- <対象ファイル>`）。不一致ならローカルファイルはbaseブランチの状態として扱う。

### Step 2: コンテキスト収集（エージェント起動前に自分でやる）

- 変更ロジックと同種のパターン（同じ値をDBに保存/比較する別usecase等）をgrepで横断的に洗い出す。
- 変更箇所の呼び出し元（バリデーションの有無、型保証がランタイムでも成立するか）を確認する。
- 書き込み側だけでなく対になる比較・読み取り側のコードも見て整合性を確認する。

### Step 3: 専門エージェントを並列起動

diffが小さくても、`pr-review-toolkit` プラグインの専門エージェントと karaage-tools の自作レビューエージェントを `Agent` ツール（`subagent_type` 指定）で並列に投げる。汎用エージェントで代替しない。

以下を**既定ですべて起動し、1つのメッセージで同時に投げる**。外してよいのは、diff に該当するコードが1行も無いと言い切れるときだけ。迷ったら起動する。観点が重なるエージェントがあっても、それを理由に片方を省かない。

`pr-review-toolkit`:

- `pr-review-toolkit:code-reviewer`（常に起動）
- `pr-review-toolkit:code-simplifier`（常に起動）: ファイルを直接書き換えるエージェントなので、「コードを編集せず、簡略化の提案を差分つきで返すだけにせよ」と必ず指示する
- `pr-review-toolkit:pr-test-analyzer`: テストの追加/変更に加え、テストが要りそうなロジック変更なのにテストが無いケースも見る
- `pr-review-toolkit:silent-failure-hunter`: catch/フォールバック/リトライ/デフォルト値による握りつぶし、外部呼び出しの失敗経路
- `pr-review-toolkit:type-design-analyzer`: 型・interface・スキーマ・DTO・関数シグネチャの追加/変更
- `pr-review-toolkit:comment-analyzer`: コメント・docstring・README等のドキュメントの追加/変更

`karaage-tools`（観点は各エージェントの定義に書いてあるので、指示で繰り返さない）:

- `karaage-tools:design-reviewer`（常に起動）: 層責務分離・秘密情報・SSoT・疎結合・シンプルさ・プロジェクト固有の不変条件
- `karaage-tools:typescript-reviewer`: TypeScriptファイルの変更
- `karaage-tools:backend-reviewer`: API/サーバー処理の変更
- `karaage-tools:frontend-reviewer`: UIの変更

省いたエージェントがあれば、Step 4 の冒頭にその名前と理由を1行ずつ書く。
各エージェントへの指示に含めるもの:

- diff全文
- 既知のコンテキスト（Step 2 の内容。重複調査を避けるため）
- 検証してほしい具体的な問い
- 「該当なしならその通り報告してよい、無理に問題を作るな」と明記

### Step 4: 集約してユーザーに提示

- Critical/Important/Suggestions ではなく確信度ラベルで分類する: `[must]`（確実に直すべき欠陥）/ `[should]`（推奨だが必須でない）/ `[imo]`（自分の見解・判断）/ `[q]`（ユーザーの判断が要る問い）。
- スコープ外だが関連する発見（同型バグが別ファイルに残っている等）は明示的に分けて報告する。
- 前置き・相槌なしで結論から。同じ主張の言い換え水増しをしない。「やって当然の確認」は書かず、副次的影響・関連issue/PRとの紐付け・見落としやすい設計判断を優先する。
- 指示がない限り「次にやること」のまとめは書かない。指摘を列挙して終える。

### Step 5: GitHubへの投稿（ユーザー承認後）

```sh
gh api repos/<owner>/<repo>/pulls/<番号>/files --jq '.[] | {filename, patch}'
```

で実際のdiff hunkと行番号を確認してから組み立てる（推測で行番号を数えない）。

- インラインコメントはdiffに含まれる行にしか打てない。対象ファイルがPRの差分に含まれない場合はreviewの`body`（全体コメント）に回す。
- コメント本文の冒頭に確信度タグ（`[must]`等）を付ける。
- コメント本文の末尾に空行を挟んで署名を付ける: `<img src="https://claude.ai/favicon.ico" width="12" height="12"/> Claude Code`
- 一時JSONファイルに書き出し、以下で投稿する（シェルエスケープでの直書きは避ける）。

```sh
gh api --method POST repos/<owner>/<repo>/pulls/<番号>/reviews --input <ファイル>
```

- `event` は基本 `COMMENT`（本人が自分のPRをレビューする場合、APPROVE/REQUEST_CHANGES は権限エラーになりうる）。

## 注意事項

- GitHubへのコメント投稿は外向きの副作用を伴う。ユーザーの明示的な承認を得てから実施する。
- 日本語・記号を含む本文は一時ファイルに書いてから `--input`/`-F body=@<file>` で渡す（シェル経由のエスケープ崩れを避ける）。
