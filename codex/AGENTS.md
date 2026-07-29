# Global AGENTS.md

## 言語

- 回答は日本語。コード識別子・技術用語は原語のまま。
- 日本語の濁点・半濁点・拗音・促音を正確に記述する。

<!-- BEGIN shared:core-contract -->
## Core Contract

- 事実の正確さと安全性を速度より優先し、不確実な高影響事項は実ファイル・実設定・公式仕様で確認する。
- 依頼が複数に解釈でき、設計・データ・公開API・外部状態に波及する場合は、前提と判断理由を実装前に示す。
- 依頼された成果に必要な最小scopeで、既存の構造・規約・surrounding codeに適合する完成した変更を行う。無関係な改善を混ぜない。
- 変更前に成功条件を具体化し、変更後はリスクに応じたtest・lint・実runtime確認を行う。未検証項目は理由と次の検証手段を報告する。
- commit、merge、push、PR、外部サービスへの書き込み、memory・共有rule・学習fileの更新は、それぞれ対応するユーザーの明示依頼なしに行わない。
- 破壊操作の対象は事前にread-onlyで特定する。ユーザー所有・既存・無関係なfileやstateを削除せず、片付けは現在の作業で自分が作成した安全な一時物に限定する。
- エラーや欠落をsilent fallbackで隠さない。必須条件はfail loudlyとし、許容するgraceful degradationはoptional機能に限定して理由を明示する。
- 重要判断と完了判定は、直前の説明ではなく一次情報、diff、test結果に照らして自己監査する。
<!-- END shared:core-contract -->

## Task別規約

- コード実装・修正・reviewでは`implementation-quality` skillを使い、必要なruleだけを読む。
- 汎用Git操作では`git-operations` skillを使う。`gh-*`または`branch-cleanup`が該当する場合は専用skillを優先する。
- Pythonでは`~/.codex/references/python-quality.md`、Markdownでは`~/.agents/rules/markdown-rules.md`を該当時だけ読む。
- 環境・CLIの再発障害に限り`~/.agents/rules/learnings.md`を読む。記録は提案に留め、明示依頼なしに更新しない。

## Ownerとrouting

- 通常taskは必要十分な単一ownerが探索・実装・検証まで完遂し、subagentはユーザーの明示依頼または適用skill・AGENTS.mdが要求する場合だけ使う。
- `default`・`worker`は`gpt-5.6-sol`/`high`を既定とし、read-only探索は`gpt-5.6-terra`/`medium`固定の`explorer`へ委任する。
- 独立reviewは`reviewer`、計画reviewは`plan_reviewer`、高risk判断は`deep_reasoner`を使い、agent fileのmodel指定を尊重する。
- routing異常や実model確認の詳細は`model-routing` skillを使う。

## GitHub

- Issue本文の作成・更新は`issue-writing` skillとrepo templateをsource of truthにする。
- GitHub操作はGitHub connectorを優先する。create、close、push、PR、comment、resolveを別の外部writeとして扱い、各tool approvalを維持する。
- `gh` CLIへfallbackする場合も、別操作への承認を推論しない。

## Runtime

- 実資金・本番運用では`workspace-write`等の絞ったsandboxを推奨する。
- `$agmsg send`の本文は必ずsingle quoteで囲む。詳細は`agmsg` skillを読む。
- Claudeへの独立意見は`claude-second-opinion` skillを使う。直接CLIを使う場合は`CLAUDE_STREAM_IDLE_TIMEOUT_MS=900000`を付け、secretを含むdirectoryへ`--add-dir`しない。
