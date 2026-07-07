---
name: x-article-to-markdown
description: Use when the user shares an X (Twitter) post URL/ID and wants its content as text or a Markdown file — Article（ロングフォーム）・Note Tweet（長文）・通常ツイートのいずれも対象 — especially after a plain fetch fails（x.com が 402 / oEmbed が本文なし / JS shell のみ / 「ポストが取得できない」「ツイートをmd化して」）. Retrieves the body plus images/video that WebFetch, curl, oEmbed, and fxtwitter cannot.
allowed-tools: Bash
---

# X Post → Markdown

## Overview

X の投稿本文（特に **Article** と **Note Tweet** の全文）は、URL を直接 fetch しても取得できない。`WebFetch` は 402、oEmbed / fxtwitter は本文なし（Note Tweet は 280 字で切れる）、素の scraping は JS shell しか返らない。

**正解の経路**: tweet を GraphQL `TweetResultByRestId` で取得し、`withArticlePlainText` / `withArticleRichContentState` の field toggle を有効化する。同梱スクリプトがこの手順（queryId 動的抽出 → guest token 発行 → GraphQL → Markdown 化）を一括実行する。認証・API キー不要。

投稿タイプは自動判定される: Article → `article.md`（Draft.js 変換）、Note Tweet / 通常ツイート → `tweet.md`（本文 + richtext + t.co 展開 + 添付メディア）。

## When to Use

- X 投稿の URL/ID を渡されて「内容を確認して」「md 化して」と言われた
- `WebFetch` が X で 402、または oEmbed/fxtwitter がリンクだけ返して本文が取れない
- 投稿内の画像・動画・引用ポスト・コードブロックも残したい

**対象外**: 削除・非公開・年齢制限投稿。Article の記事 URL 単体（seed tweet が不明な場合）→ 記事を投稿している `status` URL が必要。

## Usage

```bash
python3 ~/.claude/skills/x-article-to-markdown/x_article_md.py \
  <tweet_status_url_or_id> --out <DIR>
```

- 入力は **status URL**（`https://x.com/<user>/status/<id>`）または **生の tweet id**
- 既定でメディアを `<DIR>/assets/` に DL し、相対参照の自己完結 MD を生成
  - Article → `<DIR>/article.md` / Note Tweet・通常ツイート → `<DIR>/tweet.md`
- 生 GraphQL レスポンスは `<DIR>/raw.json` に保存（再変換・検証用）

主なフラグ（詳細は `--help`）:

| フラグ | 用途 |
|--------|------|
| `--remote-media` | DL せず `pbs.twimg.com` の URL 参照のまま（軽量・オフライン不可） |
| `--json-only` | GraphQL 生 JSON だけ保存して終了 |

## What it reconstructs

**Article**（Draft.js `content_state` を忠実に変換）:

- 見出し / 段落 / 箇条書き / **太字** / インラインリンク
- 画像（原文キャプション付き）・動画（サムネのクリックで mp4／MD は動画埋め込み不可のため）
- 引用ポスト（リンク化）・コードブロック（` ```lang `）・カバー画像・公開日時

**Note Tweet / 通常ツイート**:

- 全文（Note Tweet は legacy の 280 字ではなく `note_tweet` 側の全文）
- richtext（太字/斜体）・t.co リンクの `[display_url](expanded_url)` 展開
- 添付画像・動画（サムネ + mp4）・引用ポスト（リンク化）・投稿者・投稿日時

## Common Mistakes

- **Article の記事 URL を直接 fetch する** → 本文は HTML に無い。必ず seed tweet 経由。
- **queryId をハードコードする** → X の更新で変わる。スクリプトは毎回 bundle から動的抽出する。
- **oEmbed/fxtwitter で済ませる** → 通常ツイートなら取れるが、Article 本文と Note Tweet 全文は取れない。

## Fragility (No Fallback)

`BEARER`（公開 guest bearer）と queryId は X 側の更新で失効しうる。その場合スクリプトは**握りつぶさず例外で落ちる**。queryId 抽出失敗・GraphQL 非 200・tweet 取得不能（削除/非公開/年齢制限）は、それぞれ明示エラーになる。失効時は `x_article_md.py` 冒頭の `BEARER` を最新の web app 値へ更新する。
