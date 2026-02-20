---
description: "Vanta APIに問い合わせてセキュリティ・コンプライアンス情報を取得する。"
argument-hint: "<質問や操作内容>"
---

# vanta

Vanta APIを使って、セキュリティ・コンプライアンス関連の情報を取得する。

## 前提

- `~/.vanta/.env` に `client_id` と `client_secret` を含むJSON形式のクレデンシャルファイルが存在すること
- API: https://api.vanta.com

## ワークフロー

### 1. OAuthトークンの取得

Bashツールで以下を実行し、アクセストークンを取得する。

```sh
VANTA_CREDS=$(cat ~/.vanta/.env)
CLIENT_ID=$(echo "$VANTA_CREDS" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$VANTA_CREDS" | jq -r '.client_secret')

TOKEN_RESPONSE=$(curl -s "https://api.vanta.com/oauth/token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"$CLIENT_ID\",\"client_secret\":\"$CLIENT_SECRET\",\"grant_type\":\"client_credentials\",\"scope\":\"vanta-api.all:read\"}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
echo "Token acquired: ${ACCESS_TOKEN:0:20}..."
```

トークン取得に失敗した場合は `~/.vanta/.env` のクレデンシャルが無効である旨を伝え、Vantaダッシュボードの Developer console での再発行を案内する。

### 2. ユーザーの要求に応じたAPI呼び出し

取得したトークンを使い、ユーザーの質問「$1」に対応するVanta APIエンドポイントを呼び出す。

利用可能なエンドポイント（GETリクエスト、ベースURL: `https://api.vanta.com/v1`）:

| カテゴリ | エンドポイント | 説明 |
|---------|-------------|------|
| テスト | `/tests` | セキュリティテスト一覧 |
| フレームワーク | `/frameworks` | コンプライアンスフレームワーク一覧 |
| コントロール | `/controls` | セキュリティコントロール一覧 |
| リスク | `/risks` | リスク一覧 |
| インテグレーション | `/integrations` | 接続済みインテグレーション一覧 |
| ベンダー | `/vendors` | ベンダー一覧 |
| ドキュメント | `/documents` | ドキュメント一覧 |
| ポリシー | `/policies` | ポリシー一覧 |
| 人員 | `/people` | 人員一覧 |
| 脆弱性 | `/vulnerabilities` | 脆弱性一覧 |
| PC管理 | `/monitored_computers` | 管理対象コンピュータ一覧 |
| トラストセンター | `/trust_centers` | トラストセンター情報 |

API呼び出し例:

```sh
curl -s "https://api.vanta.com/v1/tests" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" | jq .
```

ページネーションがある場合は `pageSize` と `pageCursor` パラメータを使用する。

### 3. 結果の整理と出力

APIレスポンスを整形し、ユーザーの質問に対する回答として提示する。

```markdown
## Vanta 情報

[整形した結果]

---
*Source: Vanta API (api.vanta.com)*
```

## 注意事項

- このスキルは読み取り専用（read）のAPIアクセスのみを行う。データの変更・作成・削除は行わない
- 大量データの場合はページネーションを使って必要な分だけ取得する
- レスポンスに含まれる機密情報（トークン、シークレット等）はユーザーに表示しない
