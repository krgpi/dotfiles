---
description: "アプリのUIコードからモックアップ画像（PNG）を生成する。"
argument-hint: "<生成したい画面の説明。例: 'QuickCaptureに文字入力中の状態' 'タスク一覧+GTD'>"
---

# mock-ui

アプリのソースコードを読み取り、実際のデザインシステムに忠実なUIモックアップをHTMLで作成し、Playwrightで@2xのPNGスクリーンショットとして出力する。

## いつ使うか

- LPやドキュメントに挿入するUI画像が必要なとき
- アプリを起動せずにUIのスクリーンショットが欲しいとき
- 特定の操作状態（入力中、メニュー展開中、複数選択中など）のキャプチャが必要なとき

## 引数の解釈

「$1」を生成したいモックアップ画面の説明として解釈する。複数の画面を一度に依頼された場合は、それぞれ個別のHTMLファイルとスクリーンショットを生成する。

## ワークフロー

### Phase 1: デザインシステムの調査

1. アプリのソースコードの場所を特定する（CLAUDE.md、package.json、既知のパスから推測）
2. **Explore エージェント** を使って以下を調査する:
   - グローバルCSS / Tailwind設定（カラーパレット、フォント、角丸、影）
   - レイアウト構造（サイドバー、メインエリア、ドロワー）
   - 対象機能のコンポーネント（ファイルパス、props、Tailwindクラス、状態管理）
   - アイコン（lucide-react等のアイコンライブラリ）
3. 調査結果をもとに、デザインの要点を整理する:
   - カラーパレット（背景、テキスト、ボーダー、アクセント）
   - フォントファミリーとサイズスケール
   - コンポーネントの構造とスタイリングパターン

### Phase 2: HTMLモックアップ作成

1. スクラッチパッドディレクトリにHTMLファイルを作成する
2. 各HTMLファイルは以下の要件を満たす:
   - **自己完結**: 外部依存なし（CSSはすべてインライン、SVGアイコンも埋め込み）
   - **固定サイズ**: `body` に `width` と `height` を指定（通常 800x520 程度）
   - **overflow: hidden**: スクロールバーが出ないようにする
   - **フォント**: Google Fonts の `@import` でWeb fontを読み込むか、`system-ui` フォールバック
   - **リアルなデータ**: ユーザーが指定したテーマに合ったダミーコンテンツを使用
   - **状態の表現**: 入力中のカーソル（`animation: blink`）、ホバー状態、選択状態、展開メニューなどをCSSで静的に再現
3. デザインシステムの調査結果に忠実に、実際のアプリと見分けがつかないレベルを目指す

### Phase 3: Playwrightでスクリーンショット生成

1. スクラッチパッドに screenshot スクリプト（`.mjs`）を作成する:

```javascript
import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const screens = [
  { name: '<名前>', file: '<HTMLファイル名>', width: 800, height: 520 },
];

const browser = await chromium.launch();
for (const s of screens) {
  const page = await browser.newPage({
    viewport: { width: s.width, height: s.height },
    deviceScaleFactor: 2,
  });
  await page.goto(`file://${join(__dirname, s.file)}`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: join(__dirname, `${s.name}.png`), type: 'png' });
  await page.close();
}
await browser.close();
```

2. Playwrightが未インストールの場合:
   - `npm init -y && npm install playwright` をスクラッチパッドで実行
   - `package.json` の `"type"` を `"module"` に変更
   - `npx playwright install chromium` でブラウザをインストール
3. スクリプトを実行してPNGを生成
4. 生成した画像を `Read` で確認し、問題があれば修正して再生成

### Phase 4: 出力

1. 生成した画像をユーザーの作業ディレクトリにコピーする
2. `SendUserFile` で画像をユーザーに送信する
3. HTMLへの挿入が必要な場合は、挿入位置をユーザーに確認してから実施する

## 注意事項

- モックアップはあくまでコードベースから推測した近似である旨をユーザーに伝える
- 実際のアプリを起動してキャプチャするほうが正確であることを初回に案内する
- ダミーコンテンツのテーマはユーザーに合わせる（指定がなければ一般的なトピックを使用）
- Retina（@2x）がデフォルト。通常解像度が必要な場合は `deviceScaleFactor: 1` にする
