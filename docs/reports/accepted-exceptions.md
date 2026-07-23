# Accepted exceptions（例外台帳）

## Current state

**active exception: 0**

この台帳は、要件からの逸脱を明示的な owner-authored decision record と結び付けるためのもの。成果物自身の記述や「成果物を受け入れれば追認」という循環規定は承認証跡として扱わない。

## Closed records

| ID | 旧論点 | v9 での解消 | 状態 |
|---|---|---|---|
| EX-001 | `break-consensus` に加えて `codex/skills/python-quality` が純増し、「新しい skill は1つだけ」と形式上衝突 | Python 品質ガイドを非 skill の遅延参照 `codex/references/python-quality.md` へ移動。新規 skill behavior / directory は `break-consensus` の1件のみ | **CLOSED — exception 不要** |
| EX-002 | `autoMemoryEnabled: true` により session 開始時の可変注入量が残る | user settings を `autoMemoryEnabled: false` に変更。常時 learnings import と native auto memory の双方を無効化 | **CLOSED — exception 不要** |

新しい例外を登録する場合は、承認者・日時・対象要件・対象 commit/artifact hash・明示的な承認文・失効条件を含む外部 decision record を参照すること。
