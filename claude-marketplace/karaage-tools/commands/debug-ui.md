---
description: "UIのスタイリング問題をブラウザ上で診断する。"
argument-hint: "<問題の説明 or URL or CSSセレクタ>"
---

# debug-ui

Chrome拡張のMCPブラウザツールを使い、UIのスタイリング・レイアウト問題を診断する。

## 引数の解釈

「$1」を以下のように解釈する:

- **URLの場合** (`http`, `https`, `localhost` で始まる): そのURLにナビゲートしてから診断を開始
- **CSSセレクタの場合** (`.`, `#`, `[` で始まる): アクティブタブでそのセレクタの要素を重点的に調査
- **それ以外**: 問題の説明として解釈し、アクティブタブ上で該当箇所を特定する

## ワークフロー

### Phase 0: タブ準備

1. `tabs_context_mcp` でMCPタブグループの情報を取得する
2. 引数がURLの場合: タブに `navigate` でそのURLに遷移する
3. URLでない場合: 現在のアクティブタブを使用する
4. タブが存在しない場合: ユーザーにデバッグ対象のページをChromeで開くよう案内して中断する

### Phase 1: 現状の記録

1. **スクリーンショット撮影**
   `computer` で `action: "screenshot"` を実行し、現在の状態を視覚的に記録する。

2. **DOM構造の取得**
   `read_page` で `depth: 8` でページの要素階層を取得する。

3. **問題箇所の特定**
   - 引数がCSSセレクタの場合: `find` または `javascript_tool` でその要素を特定し `ref_id` を得る
   - 問題の説明の場合: スクリーンショットとDOM構造から該当箇所を推定し、`find` で対象要素の `ref_id` を取得する

### Phase 2: スタイル詳細分析

対象要素とその親要素に対して `javascript_tool` で以下のスクリプトを実行する。
`<SELECTOR>` は Phase 1 で特定した要素のセレクタに置き換える。

```js
(function() {
  const el = document.querySelector('<SELECTOR>');
  if (!el) return { error: 'Element not found' };
  const cs = getComputedStyle(el);
  const rect = el.getBoundingClientRect();
  const parent = el.parentElement;
  const parentCs = parent ? getComputedStyle(parent) : null;
  const info = {
    tagName: el.tagName, className: el.className, id: el.id,
    rect: { top: Math.round(rect.top), left: Math.round(rect.left), width: Math.round(rect.width), height: Math.round(rect.height) },
    visible: rect.width > 0 && rect.height > 0 && cs.display !== 'none' && cs.visibility !== 'hidden',
    layout: {
      display: cs.display, position: cs.position, float: cs.float,
      flexDirection: cs.flexDirection, flexWrap: cs.flexWrap,
      justifyContent: cs.justifyContent, alignItems: cs.alignItems,
      gridTemplateColumns: cs.gridTemplateColumns, gridTemplateRows: cs.gridTemplateRows,
    },
    boxModel: {
      width: cs.width, height: cs.height,
      minWidth: cs.minWidth, maxWidth: cs.maxWidth,
      minHeight: cs.minHeight, maxHeight: cs.maxHeight,
      padding: cs.padding, margin: cs.margin, border: cs.border, boxSizing: cs.boxSizing,
    },
    overflow: {
      overflow: cs.overflow, overflowX: cs.overflowX, overflowY: cs.overflowY,
      isOverflowingX: el.scrollWidth > el.clientWidth,
      isOverflowingY: el.scrollHeight > el.clientHeight,
    },
    stacking: {
      zIndex: cs.zIndex, opacity: cs.opacity, transform: cs.transform, isolation: cs.isolation,
    },
  };
  if (parentCs) {
    info.parent = {
      tagName: parent.tagName, className: parent.className,
      display: parentCs.display, position: parentCs.position,
      overflow: parentCs.overflow, width: parentCs.width, height: parentCs.height,
    };
  }
  return info;
})()
```

### Phase 3: アンチパターン検出

`javascript_tool` で以下のスクリプトを実行し、ページ全体の一般的なCSS問題を検出する:

```js
(function() {
  const issues = [];
  const vw = window.innerWidth;
  document.querySelectorAll('*').forEach(el => {
    const rect = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    const sel = el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/)[0] : '');
    // ビューポートはみ出し
    if (rect.right > vw + 1 && rect.width > 0) {
      issues.push({ type: 'horizontal-overflow', selector: sel, right: Math.round(rect.right), vw });
    }
    // テキスト切れ
    if (el.scrollWidth > el.clientWidth + 1 && el.children.length === 0 && cs.textOverflow === 'clip' && cs.overflow !== 'hidden') {
      issues.push({ type: 'text-overflow', selector: sel, text: el.textContent?.substring(0, 40) });
    }
    // flex-shrink: 0 で溢れ
    if ((cs.display === 'flex' || cs.display === 'inline-flex') && el.parentElement) {
      Array.from(el.children).forEach(child => {
        const ccs = getComputedStyle(child);
        if (ccs.flexShrink === '0' && child.getBoundingClientRect().width > el.clientWidth) {
          issues.push({ type: 'flex-no-shrink', parent: sel, child: child.tagName.toLowerCase() });
        }
      });
    }
    // positioned without z-index
    if ((cs.position === 'fixed' || cs.position === 'absolute') && cs.zIndex === 'auto') {
      issues.push({ type: 'positioned-no-zindex', selector: sel, position: cs.position });
    }
  });
  return { count: issues.length, issues: issues.slice(0, 20) };
})()
```

### Phase 4: レスポンシブテスト

以下の手順でテストする:

1. **元のウィンドウサイズを記録**
   `javascript_tool` で `({ width: window.outerWidth, height: window.outerHeight })` を実行して保存する。

2. **各ブレークポイントでテスト**
   以下の順に `resize_window` → `computer(screenshot)` を繰り返す:

   | 名前 | 幅 | 高さ |
   |------|------|------|
   | sm | 640 | 900 |
   | md | 768 | 1024 |
   | lg | 1024 | 768 |
   | xl | 1280 | 800 |
   | 2xl | 1536 | 864 |

   各サイズで視覚的に問題が見つかった場合は、Phase 3 のアンチパターン検出スクリプトを再実行する。

3. **元のサイズに復元**
   手順1で記録したサイズに `resize_window` で戻す。

### Phase 5: ソースコード相関

1. **Reactコンポーネント名の取得**
   `javascript_tool` で以下を実行:

   ```js
   (function() {
     const el = document.querySelector('<SELECTOR>');
     if (!el) return null;
     const key = Object.keys(el).find(k => k.startsWith('__reactFiber$') || k.startsWith('__reactInternalInstance$'));
     if (!key) return { note: 'React fiber not found' };
     let fiber = el[key];
     const components = [];
     while (fiber) {
       if (fiber.type && typeof fiber.type === 'function') {
         components.push(fiber.type.displayName || fiber.type.name || 'Anonymous');
       }
       fiber = fiber.return;
       if (components.length >= 5) break;
     }
     return { componentTree: components };
   })()
   ```

2. **Tailwindクラスの分類**
   `javascript_tool` で以下を実行:

   ```js
   (function() {
     const el = document.querySelector('<SELECTOR>');
     if (!el || typeof el.className !== 'string') return null;
     const classes = el.className.split(/\s+/).filter(Boolean);
     return {
       layout: classes.filter(c => /^(flex|grid|block|inline|hidden|contents|justify|items|self|place|gap|order)/.test(c)),
       spacing: classes.filter(c => /^-?[mp][xytblrse]?-/.test(c)),
       sizing: classes.filter(c => /^-?(w-|h-|min-|max-|size-)/.test(c)),
       positioning: classes.filter(c => /^(relative|absolute|fixed|sticky|static|top-|right-|bottom-|left-|inset-|z-)/.test(c)),
       responsive: classes.filter(c => /^(sm:|md:|lg:|xl:|2xl:)/.test(c)),
       overflow: classes.filter(c => /^overflow/.test(c)),
       all: classes,
     };
   })()
   ```

3. **ソースファイルの特定**
   コンポーネント名が判明したら:
   - `Glob` で `**/<ComponentName>.tsx`, `**/<ComponentName>.jsx`, `**/<component-name>.tsx` を検索
   - `Grep` で `function <ComponentName>` や `export.*<ComponentName>` を検索
   - 見つかったファイルを `Read` で読み、問題の原因となるスタイル定義（className, style prop, CSS Modules）を特定する

4. **Hydrationエラーの確認**
   `read_console_messages` で `pattern: "hydrat|mismatch|Warning.*did not match"` を検索し、Next.js固有のスタイル不一致を確認する。

### Phase 6: 診断レポート

以下の形式で結果をまとめてユーザーに提示する:

```markdown
# UI 診断レポート

## 概要
[問題の要約を1-3文で]

## 検出された問題

### 1. [問題タイトル]
- **要素**: `<セレクタ>`
- **コンポーネント**: `<ComponentName>` (`<ファイルパス:行番号>`)
- **原因**: [CSSプロパティの問題の説明]
- **修正案**:
  [具体的なコード変更をdiff形式で提示]

## レスポンシブ状況
| ブレークポイント | 状態 | 問題 |
|---|---|---|
| sm (640px) | OK/NG | [説明] |
| md (768px) | OK/NG | [説明] |
| lg (1024px) | OK/NG | [説明] |
| xl (1280px) | OK/NG | [説明] |
| 2xl (1536px) | OK/NG | [説明] |

## 推奨修正（優先度順）
1. [最も影響の大きい修正 — ファイルパスと具体的な変更内容]
2. [次の修正]
```

## 注意事項

- **診断のみ行い、ファイルの変更は行わない**。修正案は提案として提示し、ユーザーの確認後に別途実施する
- コンソールのエラー・警告も `read_console_messages` で確認し、CSS関連のものがあれば報告する
- SSR/CSR の差異に注意: hydration mismatch はスタイル問題の原因になりうる
- Tailwind の `tailwind.config.js` / `tailwind.config.ts` のカスタマイズも必要に応じて調査する
- 要素数が非常に多いページ（5000以上）ではPhase 3のスキャンを問題箇所周辺に絞る
