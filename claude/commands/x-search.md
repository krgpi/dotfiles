---
description: "X(Twitter)で特定トピックをリサーチする。"
argument-hint: "<検索トピック>"
---

# x-search

X(Twitter)上の情報を検索・収集し、リサーチレポートを作成する。

## 前提

環境変数 `XAI_API_KEY` と `X_BEARER_TOKEN` が設定されていること。

## ワークフロー

### Step 1: xAI Grok で X 検索（メイン）

xAI の Grok API に `x_search` ツールを使わせて、トピック「$1」に関するX上の投稿をAI分析付きで取得する。

```sh
curl -s https://api.x.ai/v1/chat/completions \
  -H "Authorization: Bearer $XAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "grok-3-mini",
    "search_parameters": {
      "mode": "on",
      "sources": ["x"],
      "recency": "week",
      "max_search_results": 20
    },
    "messages": [
      {
        "role": "system",
        "content": "You are an X/Twitter research analyst. Search X for the given topic and provide: 1) Key opinions and trends (positive/negative), 2) Notable tweets with high engagement, 3) Expert perspectives, 4) Counterarguments and concerns. Include tweet URLs, usernames, and engagement metrics where available. Respond in Japanese."
      },
      {
        "role": "user",
        "content": "X上で「$1」について調査してください。主要な意見、注目ツイート、賛否両論を整理してください。"
      }
    ]
  }'
```

レスポンスの `choices[0].message.content` を取得し、引用されたソースURLも抽出する。

### Step 2: X API v2 で生データ補完

Grok の結果を補完するため、X API v2 で直接ツイートを検索する。エンゲージメント指標付きの生データが取れる。

```sh
curl -s -G "https://api.twitter.com/2/tweets/search/recent" \
  --data-urlencode "query=$1 -is:retweet lang:ja" \
  --data-urlencode "tweet.fields=created_at,public_metrics,author_id" \
  --data-urlencode "expansions=author_id" \
  --data-urlencode "user.fields=name,username,public_metrics" \
  --data-urlencode "max_results=20" \
  --data-urlencode "sort_order=relevancy" \
  -H "Authorization: Bearer $X_BEARER_TOKEN"
```

結果の `data[]` からツイート本文・いいね数・RT数、`includes.users[]` からユーザー名を取得する。

### Step 3: Web検索で一次情報を補完

WebSearchツールで公式ドキュメント・GitHub・ブログ等の一次情報も検索する。

### Step 4: 情報の統合・分析

Step 1-3 の結果を統合し、以下の構造で整理する:

- **要約**: トピックの現状を1-3文で
- **主要な意見・動向**: ポジティブ/ネガティブに分類
- **注目ツイート**: エンゲージメント上位の投稿（いいね・RT数付き）
- **一次情報**: 公式発表、ドキュメント、データ
- **反論・懸念**: 批判的な意見や指摘されているリスク

## 出力フォーマット

```markdown
# X リサーチレポート: [トピック]

調査日時: YYYY-MM-DD

## 要約
[1-3文の概要]

## 主要な意見・動向
### ポジティブ
- [意見] — @username, ❤️ N, 🔁 N (URL)

### ネガティブ / 懸念
- [意見] — @username, ❤️ N, 🔁 N (URL)

## 注目ツイート
- @username: "[ツイート内容の要約]" ❤️ N, 🔁 N (URL)

## 一次情報・公式ソース
- [情報] (URL)

## Sources
- [URL一覧]
```

## 注意事項

- X上の投稿は二次情報として扱い、一次情報（公式ドキュメント等）を優先する
- 統計・数字には「[日付] 時点」を付記する
- 長文の直接引用は避け、要約+URLで追えるようにする
- X API v2 の検索は直近7日間のみ対象（Recent Search）
