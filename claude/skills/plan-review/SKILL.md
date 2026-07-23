---
name: plan-review
description: "Use when an implementation plan needs review before execution（計画立案後・実装着手前、「計画をレビューして」/plan-review）. 独立 context の plan-reviewer サブエージェント 1 体による実行前計画レビュー（実現可能性・完全性・スコープ&リスクの 3 観点）。"
---

# 実行前計画レビュー

実装計画を、独立 context の `plan-reviewer` サブエージェント 1 体で監査する（実現可能性・完全性・スコープ&リスクの 3 観点を 1 回で網羅）。

## Arguments

$ARGUMENTS

## Instructions

### Step 1: 計画の特定

- **引数にファイルパスがある場合**（別セッションモード）: 指定ファイルを計画として読み込む。レビュアーは自らコードベースを探索して検証する
- **引数が空の場合**（同一セッションモード）: この会話で最近作成・議論された計画を対象にする。見つからなければユーザーに確認する

### Step 2: コンテキストの収集

計画本文に加え、存在すれば以下を読み込んでレビュアーへ渡す:

- プロジェクトの CLAUDE.md / `claudedocs/learnings.md`
- `~/.agents/rules/learnings.md`
- 同一セッションモードでは、計画策定時の主要な意思決定と関連ファイル一覧

### Step 3: plan-reviewer を起動

Agent ツールで `plan-reviewer` を 1 体起動する。プロンプトには**計画の全文**（要約・省略禁止）と Step 2 のコンテキストを含める。別セッションモードでは「参照ファイル・依存の実在をコードベースで検証すること」を明示する。

### Step 4: 結果の保存と報告

1. レビュー結果を `claudedocs/reviews/plan-review-[YYYYMMDD-HHMM].md` に保存する（ディレクトリがなければ作成）
2. ユーザーへ報告する: 総合判定（APPROVE / APPROVE_WITH_CHANGES / REQUEST_REVISION / REJECT）、BLOCKER/WARNING/INFO 件数、最重要指摘 Top 3、保存パス
3. BLOCKER がある場合は、計画修正 → 必要なら再レビューを提案する（自動では修正しない）
