# Accepted exceptions（例外台帳）

## Current state

**active exceptions: 2**

この台帳は、要件からの逸脱を明示的な owner-authored decision record と結び付けるためのもの。成果物自身の記述や「成果物を受け入れれば追認」という循環規定は承認証跡として扱わない。

## Active records

| ID | 承認者・日時 | 対象 | owner-authored decision | 対象 artifact | 失効条件 |
|---|---|---|---|---|---|
| EX-003 | repository owner / 2026-07-24（初回）・2026-08-31、2026-09-25（再承認） | M-04/C-02 の全 Bash approval、bypass lockout、fail-closed sandbox | この作業会話で「完全に以前どおり: bypassPermissions に戻す」と明示。再承認: 2026-08-31 の /gh-roadmap-drive 13 判断ゲート（#7）で、下記差分要約を確認のうえ「両方を継続承認」を選択（session_01PX4vcUjjwP3wbZ5hCFjyUb）。再承認: 2026-09-25 の近代化 Phase 7 の作業 session（f4c081cf-1893-426c-9e11-d2bc0476e4ae）で、下記差分要約を確認のうえ「今再承認する」を選択 | `claude/managed-settings.json` SHA-256 `39a2490925354d094b55fe95dda7dc9ef74bb29639e1137b0c25ec0e63483d38`（branch `modernize/phase-7` の Phase 7 commit） | owner が prompt/sandbox policy の復元を明示するまで |
| EX-004 | repository owner / 2026-07-26（初回）・2026-08-31、2026-09-25（再承認） | Claude 5 context engineeringのnative memory推奨 | この作業会話でmemory policyとして「両方無効」を選択。再承認: 2026-08-31 の /gh-roadmap-drive 13 判断ゲート（#7）で、下記差分要約を確認のうえ「両方を継続承認」を選択（session_01PX4vcUjjwP3wbZ5hCFjyUb）。再承認: 2026-09-25 の近代化 Phase 7 の作業 session（f4c081cf-1893-426c-9e11-d2bc0476e4ae）で、artifact を managed へ移すこと（P7-Q4）と下記差分要約を確認のうえ「今再承認する」を選択 | `claude/managed-settings.json` SHA-256 `39a2490925354d094b55fe95dda7dc9ef74bb29639e1137b0c25ec0e63483d38`（branch `modernize/phase-7` の Phase 7 commit）の `autoMemoryEnabled: false`、local Codex effective setting `features.memories=false` | ownerがClaudeまたはCodexのnative memory導入を明示するまで |

EX-003 により、permission の allow と ask、sandbox の filesystem と network は現行 runtime では効かない（bypassPermissions、sandbox 無効）。deny は bypassPermissions でも有効。managed hooks は維持するが、完全な security boundary ではない。

EX-004 は、永続contextを明示的・決定的なrule、skill、project documentだけで管理するowner policyである。[Claude 5 context engineering guidance](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)に対する意図的な差異であり、「完全準拠」とは扱わない。

## Re-approval records

| ID | 再承認日 | 旧 hash（commit） | 新 hash（commit） | 差分要約 | 承認文参照 |
|---|---|---|---|---|---|
| EX-003 | 2026-08-31 | `7e1a7aabf093…`（commit `9767e77`） | `be5b9f8d3178…`（commit `50a712b`） | statusLine、PreToolUse `Agent` matcher、PostToolUse `Edit\|Write`（post-edit-lint-hook）、UserPromptSubmit（prompt-submit-hook）を追加。requiredMinimumVersion 2.1.218 → 2.1.219。`permissions.defaultMode`（bypassPermissions）、`sandbox.enabled`（false）、`skipDangerousModePermissionPrompt`（true）、`disableAutoMode`（disable）は変更なし | 2026-08-31 /gh-roadmap-drive 13 判断ゲート（#7）「両方を継続承認」（[session_01PX4vcUjjwP3wbZ5hCFjyUb](https://claude.ai/code/session_01PX4vcUjjwP3wbZ5hCFjyUb)） |
| EX-004 | 2026-08-31 | `76f03e410224…`（commit `353ae5e`） | `b192677f0450…`（commit `50a712b`） | `effortLevel` medium → xhigh。user-scope statusLine を削除（managed へ移動）。未使用の enabledPlugins 3件を削除。`autoMemoryEnabled: false` は変更なし | 2026-08-31 /gh-roadmap-drive 13 判断ゲート（#7）「両方を継続承認」（[session_01PX4vcUjjwP3wbZ5hCFjyUb](https://claude.ai/code/session_01PX4vcUjjwP3wbZ5hCFjyUb)） |
| EX-003 | 2026-09-25 | `be5b9f8d3178…`（commit `50a712b`） | `39a249092535…`（`modernize/phase-7`） | requiredMinimumVersion 2.1.219 → 2.1.281。`autoMemoryEnabled: false` を追加（EX-004 を user settings から移す）。`env` に alias の pin 4つ（`ANTHROPIC_DEFAULT_{FABLE,OPUS,SONNET,HAIKU}_MODEL`、D2）を追加。deny に `Agent(codex:codex-rescue)` を追加（OD-5）。UserPromptSubmit（prompt-submit-hook）、PostCompact（post-compact-hook）、SessionStart の session-init-hook の登録を削除（D3②、P7-Q1）。`permissions.defaultMode`（bypassPermissions）、`sandbox.enabled`（false）、`skipDangerousModePermissionPrompt`（true）、`disableAutoMode`（disable）は変更なし | 2026-09-25 近代化 Phase 7 の作業 session（f4c081cf-1893-426c-9e11-d2bc0476e4ae）「今再承認する」 |
| EX-004 | 2026-09-25 | `b192677f0450…`（`claude/settings.json`、commit `50a712b`） | `39a249092535…`（`claude/managed-settings.json`、`modernize/phase-7`） | `claude/settings.json` を repo から削除し（D5、P7-Q2）、`autoMemoryEnabled: false` を managed に移して policy で強制する（P7-Q4）。repo の `effortLevel: xhigh` は削除（D9 の値は owner が live の `modelSettings` に設定する）。Codex の `features.memories=false` は変更なし | 2026-09-25 近代化 Phase 7 の作業 session（f4c081cf-1893-426c-9e11-d2bc0476e4ae）「今再承認する」 |

## Closed records

| ID | 旧論点 | v9 での解消 | 状態 |
|---|---|---|---|
| EX-001 | `break-consensus` に加えて `codex/skills/python-quality` が純増し、「新しい skill は1つだけ」と形式上衝突 | Python 品質ガイドを非 skill の遅延参照 `codex/references/python-quality.md` へ移動。新規 skill behavior / directory は `break-consensus` の1件のみ | **CLOSED — exception 不要** |
| EX-002 | `autoMemoryEnabled: true` により session 開始時の可変注入量が残る | user settings を `autoMemoryEnabled: false` に変更。常時 learnings import と native auto memory の双方を無効化 | **CLOSED — exception 不要** |

新しい例外を登録する場合は、承認者・日時・対象要件・対象 commit/artifact hash・明示的な承認文・失効条件を含む owner-authored decision record を参照すること。台帳記載の artifact を変更する場合は、`scripts/validate-layout.sh` が hash 不一致で失敗するため、同じ変更で owner 再承認記録と SHA-256 を更新すること。
