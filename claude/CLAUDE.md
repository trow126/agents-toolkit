# Claude Code 設定

# 共有ルール（正本: ~/.agents/rules/ — Codex と共有。正本編集後は ~/.agents/bin/sync-shared-rules.sh を実行）
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
- プロジェクト固有の教訓は `claudedocs/learnings.md`（存在時）を必要時に確認する。native auto memory は計測不能な常時注入を避けるため無効
- 汎用の環境・CLI 教訓は `~/.agents/rules/learnings.md` を必要時にだけ読む（常時ロードしない。棚卸しは `/knowledge-audit`）

# owner 選択とルーティング（コスト方針）

通常タスクは、必要十分な最小コストの単一 owner が探索・実装・検証まで一貫して完遂する。owner は main セッションでよく、「常に委任」はしない。同じ context を実装と検証で再利用できる場合は handoff しない。

- 決定論的 script・静的解析で処理できる作業に LLM を使わない
- 大量の read-only 探索だけは低コスト subagent（built-in Explore 等）へ隔離し、中間結果を main context へ大量流入させない
- ドメインスペシャリスト・reviewer・`deep-reasoner` の使い分けは各 agent の description（Use when 条件）に従う。迷ったら単一 owner 既定を優先する
- subagent からの再委任は原則禁止。タスクのステップ数を委任基準にしない
- 完了判定は deterministic なテスト・lint・CI で行う
- Agent Teams / `ultracode` は experimental のため共有設定では無効。3 本以上の独立 workstream で並列化の利点が調整コストを明確に上回る大型タスクに限り、当該 machine の shell 環境変数（`export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`）で opt-in してから使う

詳細手順（高リスク判断の並列諮問・Codex peer 連携・routing 検証）は `model-routing` スキルを参照。

# private routing（machine 固有の project→specialist 対応）

- status: opt-in active config（deprecated archive ではない）
- 配置: untracked の `${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/private-routing.md`（公開リポジトリに固有名を書かない）
- 消費者と起動条件: specialist を選択する際、owner が `~/.claude/bin/private-routing-locate` で存在を確認し、exit 0 の場合のみ該当 project 節を読んで routing に反映する
- 優先順位（上が優先。競合時は上位が勝つ）: 1. 安全制約・permission・tool restriction → 2. ユーザーの明示指定 → 3. private routing の project mapping → 4. 上記の汎用ドメイン routing 原則 → 5. 標準の単一 owner 既定
- 不在時挙動: resolver が exit 1 の場合は本ファイルなしとして汎用原則（4→5）だけで判断し、エラーにしない。private 内容を成果物・ログ・外部サービスへ出力しない

# 起動運用

- `claude` は常にプロジェクトディレクトリから起動する。`$HOME` 直下からの起動は禁止（cwd 全体スキャンで RSS 15-17GB・3 分超ハングの実測あり。`.claudeignore` は起動時スキャンに効かない: 2026-04-19 検証済み）
- owner の明示選択により OS-managed policy は `bypassPermissions` を既定とし、dangerous mode confirmation を省略する。permission prompt は表示せず、sandbox も無効。permission の allow/ask/deny と sandbox の filesystem/network は現行 runtime の security boundary ではない。project/local の `permissions`・`hooks`・`sandbox` は起動前の `scripts/check-runtime.sh` と各 Bash の PreToolUse 前に `project-policy-gate` が拒否する。managed hooks は literal `.env` 読み取り、block device write、`git commit --amend` 等を事故防止として deny するが、完全な境界ではない
- `~/.claude/bin/uvw` は sandbox 無効時も利用可能だが必須ではない。Git 操作は prompt なしで実行されるため、Git workflow とユーザーの明示承認境界を厳守する
