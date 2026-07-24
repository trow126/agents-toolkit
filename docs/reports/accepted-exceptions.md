# Accepted exceptions（例外台帳）

## Current state

**active exception: 1**

この台帳は、要件からの逸脱を明示的な owner-authored decision record と結び付けるためのもの。成果物自身の記述や「成果物を受け入れれば追認」という循環規定は承認証跡として扱わない。

## Active records

| ID | 承認者・日時 | 対象 | owner-authored decision | 対象 artifact | 失効条件 |
|---|---|---|---|---|---|
| EX-003 | repository owner / 2026-07-24 | M-04/C-02 の全 Bash approval、bypass lockout、fail-closed sandbox | この作業会話で「完全に以前どおり: bypassPermissions に戻す」と明示 | `claude/managed-settings.json` SHA-256 `7e1a7aabf093d4d85f39845245795aa5c5246a424846cf4c7de4d5b128ce8a8b` | owner が prompt/sandbox policy の復元を明示するまで |

EX-003 により permission allow/ask/deny と sandbox filesystem/network は現行 runtime の enforcement ではない。managed hooks は維持するが、完全な security boundary ではない。

## Closed records

| ID | 旧論点 | v9 での解消 | 状態 |
|---|---|---|---|
| EX-001 | `break-consensus` に加えて `codex/skills/python-quality` が純増し、「新しい skill は1つだけ」と形式上衝突 | Python 品質ガイドを非 skill の遅延参照 `codex/references/python-quality.md` へ移動。新規 skill behavior / directory は `break-consensus` の1件のみ | **CLOSED — exception 不要** |
| EX-002 | `autoMemoryEnabled: true` により session 開始時の可変注入量が残る | user settings を `autoMemoryEnabled: false` に変更。常時 learnings import と native auto memory の双方を無効化 | **CLOSED — exception 不要** |

新しい例外を登録する場合は、承認者・日時・対象要件・対象 commit/artifact hash・明示的な承認文・失効条件を含む owner-authored decision record を参照すること。
