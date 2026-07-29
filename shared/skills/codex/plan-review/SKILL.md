---
name: plan-review
description: "Use when an implementation plan needs review before execution（計画立案後・実装着手前、「計画をレビューして」$plan-review）. 独立コンテキストでの実行前計画レビュー（実現可能性・完全性・スコープ&リスクの 3 観点）。"
---

# 実行前計画レビュー

実装計画を、read-only custom agent `plan_reviewer` 1体で監査する（実現可能性・完全性・スコープ&リスクの3観点を1回で網羅）。agentが利用できない場合はgeneric agentへsilent fallbackせず、`~/.codex/agents/plan_reviewer.toml`のinstall状態を報告する。

## Arguments

$ARGUMENTS

## Instructions

### Step 1: 計画の特定

- **引数にファイルパスがある場合**（別セッションモード）: 指定ファイルを計画として読み込む。レビュアーは自らコードベースを探索して検証する
- **引数が空の場合**（同一セッションモード）: この会話で最近作成・議論された計画を対象にする。見つからなければユーザーに確認する

### Step 2: コンテキストの収集

計画本文に加え、存在すれば以下を読み込んでレビュー呼び出しへ渡す:

- プロジェクトの AGENTS.md / `claudedocs/learnings.md`
- `~/.agents/rules/learnings.md`
- 同一セッションモードでは、計画策定時の主要な意思決定と関連ファイル一覧

### Step 3: 独立コンテキストでレビューを実行

native subagent interfaceで`plan_reviewer`をfull-history forkなしで1体起動し、以下のレビュー観点をプロンプトに明示する。per-spawn modelは指定せず、agent fileの`gpt-5.6-sol`/`high`を使う。プロンプトには**計画の全文**（要約・省略禁止）とStep 2のコンテキストを含める。別セッションモードでは「参照ファイル・依存の実在をコードベースで検証すること」を明示する。**計画の書き換えや実装はさせない。**

```
## 観点 1: 実現可能性（Feasibility）
- 計画が参照するファイル・クラス・関数・設定キーが実際のコードベースに存在するか検証する（実物を確認。推測で通さない）
- 依存関係・API・ライブラリの前提が現状と一致するか
- 手順の順序に依存の逆転（先に必要なものが後にある）がないか

## 観点 2: 完全性（Completeness）
- テスト戦略があるか（新規/変更コードのテスト、境界値・無効値・空ケース）
- エラーハンドリングと失敗時の挙動が定義されているか
- ロールバック/復旧手段があるか（特にデータ・スキーマ・設定変更）
- プロジェクト規約（AGENTS.md・learnings・既存パターン）への準拠
- 成功条件が最終状態で定義されているか（中間シグナルでの完了扱いは不可）

## 観点 3: スコープとリスク（Critic）
- YAGNI 違反・過剰設計・投機的汎用化はないか
- より単純なアプローチで同じ成功条件を満たせないか（あれば具体的に提示）
- セキュリティ・パフォーマンス・不可逆操作のリスク
- 依頼範囲を超える無関係変更が混入していないか

## 出力形式
## 判定: APPROVE / APPROVE_WITH_CHANGES / REQUEST_REVISION / REJECT

## BLOCKER（実装前に修正必須）
- [観点] 指摘・根拠（実ファイルの証拠）・推奨修正

## WARNING（対応推奨）
- ...

## INFO（検討事項）
- ...
```

- APPROVE: BLOCKER なし、WARNING 0-2 件
- APPROVE_WITH_CHANGES: BLOCKER なし、対応すべき WARNING あり
- REQUEST_REVISION: BLOCKER 1 件以上または WARNING 多数
- REJECT: 根本的なアプローチの問題

根拠なき指摘は出させない。各 BLOCKER には実ファイル・実行結果など独立に確認した証拠を添えさせる。

### Step 4: 結果の保存と報告

1. レビュー結果を `claudedocs/reviews/plan-review-[YYYYMMDD-HHMM].md` に保存する（ディレクトリがなければ作成）
2. ユーザーへ報告する: 総合判定（APPROVE / APPROVE_WITH_CHANGES / REQUEST_REVISION / REJECT）、BLOCKER/WARNING/INFO 件数、最重要指摘 Top 3、保存パス
3. BLOCKER がある場合は、計画修正 → 必要なら再レビューを提案する（自動では修正しない）
