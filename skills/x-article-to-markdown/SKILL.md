---
name: x-article-to-markdown
description: Use when the user shares an X (Twitter) post URL/ID that contains a long-form Article and wants its full text or a Markdown file — especially after a plain fetch fails（x.com が 402 / oEmbed が本文なし / JS shell のみ / 「記事が取得できない」「ツイートの記事をmd化して」）. Retrieves the article body plus images/video that WebFetch, curl, oEmbed, and fxtwitter cannot.
allowed-tools: Bash
---

# X Article → Markdown

## Overview

X の **Article（ロングフォーム投稿）** の本文は、記事 URL（`/i/article/<id>`）を直接 fetch しても HTML に含まれない。`WebFetch` は 402、oEmbed / fxtwitter は本文なし、素の scraping は JS shell しか返らない。

**正解の経路**: seed tweet を GraphQL `TweetResultByRestId` で取得し、`withArticlePlainText` / `withArticleRichContentState` の field toggle を有効化する。同梱スクリプトがこの手順（queryId 動的抽出 → guest token 発行 → GraphQL → Draft.js を Markdown 化）を一括実行する。認証・API キー不要。

## When to Use

- X 投稿の URL/ID を渡されて「記事内容を確認して」「md 化して」と言われた
- `WebFetch` が X で 402、または oEmbed/fxtwitter がリンクだけ返して本文が取れない
- 記事内の画像・動画・引用ポスト・コードブロックも残したい

**対象外**: 通常ツイート/Note Tweet（Article ではない）、削除・非公開・年齢制限投稿。記事 URL 単体（seed tweet が不明な場合）→ 記事を投稿している `status` URL が必要。

## Usage

```bash
python3 ~/.claude/skills/x-article-to-markdown/x_article_md.py \
  <tweet_status_url_or_id> --out <DIR>
```

- 入力は **status URL**（`https://x.com/<user>/status/<id>`）または **生の tweet id**
- 既定でメディアを `<DIR>/assets/` に DL し、相対参照の自己完結 MD（`<DIR>/article.md`）を生成
- 生 GraphQL レスポンスは `<DIR>/raw.json` に保存（再変換・検証用）

主なフラグ（詳細は `--help`）:

| フラグ | 用途 |
|--------|------|
| `--remote-media` | DL せず `pbs.twimg.com` の URL 参照のまま（軽量・オフライン不可） |
| `--json-only` | GraphQL 生 JSON だけ保存して終了 |

## What it reconstructs

Draft.js `content_state` を忠実に変換する:

- 見出し / 段落 / 箇条書き / **太字** / インラインリンク
- 画像（原文キャプション付き）・動画（サムネのクリックで mp4／MD は動画埋め込み不可のため）
- 引用ポスト（リンク化）・コードブロック（` ```lang `）・カバー画像・公開日時

## Common Mistakes

- **記事 URL を直接 fetch する** → 本文は HTML に無い。必ず seed tweet 経由。
- **queryId をハードコードする** → X の更新で変わる。スクリプトは毎回 bundle から動的抽出する。
- **oEmbed/fxtwitter で済ませる** → ツイート本文とメタは取れるが Article 本文は取れない。

## Fragility (No Fallback)

`BEARER`（公開 guest bearer）と queryId は X 側の更新で失効しうる。その場合スクリプトは**握りつぶさず例外で落ちる**。queryId 抽出失敗・GraphQL 非 200・Article 不在は、それぞれ明示エラーになる。失効時は `x_article_md.py` 冒頭の `BEARER` を最新の web app 値へ更新する。
