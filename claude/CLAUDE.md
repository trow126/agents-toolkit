# Claude Code 設定

# 共有ルール（正本: ~/.agents/rules/ — Codex と共有。正本編集後は ~/.agents/bin/sync-shared-rules.sh を実行）
@~/.agents/rules/learnings.md
@~/.agents/rules/karpathy-guidelines.md
@~/.agents/rules/no-fallback.md
@~/.agents/rules/decision-integrity.md
@~/.agents/rules/quality-priority.md
@~/.agents/rules/test-policy.md
@~/.agents/rules/git-workflow.md
@~/.agents/rules/failure-investigation.md
@~/.agents/rules/self-improvement.md
@~/.agents/rules/workspace-hygiene.md

# セッション初期化

- SessionStart hook が `git status` / `git branch` を systemMessage で自動注入する
- プロジェクト固有の教訓は `claudedocs/learnings.md`（存在時）を確認し、新しい継続的な知見は native auto memory に保存する

# owner 選択とルーティング（コスト方針）

通常タスクは、必要十分な最小コストの単一 owner が探索・実装・検証まで一貫して完遂する。owner は main セッションでよく、「常に委任」はしない。同じ context を実装と検証で再利用できる場合は handoff しない。

- 決定論的 script・静的解析で処理できる作業に LLM を使わない
- 大量の read-only 探索だけは低コスト subagent（built-in Explore 等）へ隔離し、中間結果を main context へ大量流入させない
- ドメインスペシャリスト（solidity-engineer / blockchain-security-auditor / ai-engineer / data-engineer / model-qa-specialist / sre）は、該当ドメインの高リスク・専門作業だけに使う
- 難しい設計判断・根本原因不明の障害・標準モデルの反復失敗時のみ `deep-reasoner`（reasoning model）へエスカレーションし、実装は標準モデルが行う
- 独立検証が必要な場合だけ reviewer（`code-reviewer` / `plan-reviewer`）を分離する
- subagent からの再委任は原則禁止。タスクのステップ数を委任基準にしない
- 完了判定は deterministic なテスト・lint・CI で行う
- Agent Teams / `ultracode` は、3 本以上の独立 workstream に分割でき、並列化の利点が調整コストを明確に上回る大型タスクだけに使う（experimental のため既定は単一 owner）

詳細手順（高リスク判断の並列諮問・Codex peer 連携・routing 検証）は `model-routing` スキルを参照。machine 固有の project→specialist 対応は untracked の `${XDG_CONFIG_HOME:-~/.config}/agents-toolkit/private-routing.md` に置く（公開リポジトリに固有名を書かない）。

# 起動運用

`claude` は常にプロジェクトディレクトリから起動する。`$HOME` 直下からの起動は禁止（cwd 全体スキャンで RSS 15-17GB・3 分超ハングの実測あり。`.claudeignore` は起動時スキャンに効かない: 2026-04-19 検証済み）
