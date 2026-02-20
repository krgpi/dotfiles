---
description: "Geminiに質問して調べる。"
argument-hint: "<質問内容>"
---

# ask-gemini

Gemini APIに質問を投げ、回答を取得してユーザーに提示する。

## ワークフロー

1. **質問の送信**
   Bashツールで以下のコマンドを実行し、Geminiに「$1」を問い合わせる。

   ```sh
   source ~/Developer/dotfiles/.env 2>/dev/null
   curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"contents":[{"parts":[{"text":"<質問内容>"}]}]}'
   ```

   - `.env` から `GEMINI_API_KEY` を読み込む。未設定の場合はユーザーに設定を促して中断する

2. **回答の整理**
   APIレスポンスのJSONから `.candidates[0].content.parts[0].text` を抽出し、整形してユーザーに提示する。

3. **出力**
   以下の形式で結果を表示する:

   ```markdown
   ## Gemini の回答

   [回答内容]

   ---
   *Model: gemini-2.0-flash*
   ```

## 注意事項

- Geminiの回答は参考情報として扱い、正確性はユーザー自身で検証すること
- APIキーが設定されていない場合は `export GEMINI_API_KEY=your-key` の案内を表示する
