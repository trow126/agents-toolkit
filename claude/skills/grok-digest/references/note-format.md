# grok-digest note format

The notes go into the user's Obsidian vault, which a separate clipping pipeline fills with one Markdown note per saved link and curates once a week. A Grok note follows that pipeline's clipping format, so its weekly curation adds `summary`, content tags, related-note links, and the weekly digest entry, and its search index picks the note up. Do not modify the pipeline; only write notes in its format.

## Where the vault is

The vault path is never written in this skill. `grok-digest vault` resolves it:

1. `$GROK_DIGEST_INBOX_CONFIG`, or else `config` in section `[inbox]` of `${XDG_CONFIG_HOME:-~/.config}/agents-toolkit/grok-digest.toml` (untracked, machine-local), names the pipeline's `config.toml`.
2. That file's `[vault]` `path` is the vault; notes go to `<vault>/clippings/`.

```toml
# ${XDG_CONFIG_HOME:-~/.config}/agents-toolkit/grok-digest.toml
[inbox]
config = "~/<pipeline checkout>/config.toml"
```

When this fails (exit 3; for example on a machine without the vault), report the reason and write with `--staging`: the notes go to `${XDG_STATE_HOME:-~/.local/state}/agents-toolkit/grok-digest/clippings/`, to be copied into `<vault>/clippings/` on the machine that has the vault.

## What the helper writes

`grok-digest note --url <conversation url> --title <history title> --date <conversation date> --body-file <body.md>` writes `clippings/<saved>-Grok-<slug>.md` (a numbered suffix when the name exists) with:

```yaml
---
title: "Grok: <history title>"
url: "https://x.com/i/grok?conversation=<id>"
source: grok
author: "Grok"
saved: <UTC date of the run>
status: unread
tags: [clipping, grok-digest]
---
```

- `url` is the pipeline's idempotency key. The helper refuses (exit 4) when a note with the same `url` exists; report it and do not overwrite or edit that note.
- Do not add `summary` or `curated`: the weekly curation adds them. `status`, `url`, and the user's later edits belong to the user.
- The helper appends `## 出典` with the conversation URL and date. The body must not contain `## 出典`, `## 関連ノート (auto)`, or `## Deep dive (auto)` (the pipeline owns the last two).

## Body

Write the body in Japanese, with blank lines around headings and tables. `## 会話の要約` and `## 次の一手` are required; leave out a section that has no content rather than writing an empty one.

```markdown
## 会話の要約

- what was asked and what Grok answered, in 3–6 bullets

## 関連プロジェクト

| プロジェクト | 関連度 | 使えそうな点 |
|---|---|---|
| name | 高/中/低 | concrete idea |

## 主張と根拠

| 主張 | 数値（自己申告/検証・期間） | 根拠の弱さ |
|---|---|---|
| claim | 例: 回収率 120%（自己申告、3か月） | 短期・年率換算・宣伝の兆候など |

## 深掘り

**質問**: the approved question as sent

**回答の要約**: summary with the cited posts summarized; keep 不明 as 不明

## 反論

| ID | 指摘 | 判定 | 理由 |
|---|---|---|---|
| X1 | from cross-critic | 採用/不採用 | reason |

## 次の一手

- a check to run, not a conclusion
```

Do not copy long passages of posts or of Grok's answers; summarize. Do not include anyone's profile details beyond the handle that a cited post shows.
