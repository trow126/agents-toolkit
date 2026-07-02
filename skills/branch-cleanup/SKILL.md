---
name: branch-cleanup
description: Use when the user says a branch or PR was merged and asks to clean up（「マージしたからブランチを整理して」「リモートでマージしたからローカルを整理して」「ブランチの後片付け」等）, or when stale merged branches/worktrees remain after a PR merge.
allowed-tools: Bash
---

# Branch Cleanup

マージ済みブランチの後片付けを安全に定型実行する。squash マージ（`git branch --merged` に現れない）を正しく扱う。

## 手順

1. `git status --porcelain` — 未コミット変更があれば**停止して報告**（整理はしない）
2. デフォルトブランチを特定: `git remote show origin` の HEAD branch（通常 main または master）
3. デフォルトブランチへ切替: `git checkout <default>`
4. `git pull --ff-only`
5. `git fetch --prune`
6. ローカルブランチを分類（default と現在ブランチを除く）:
   - `git branch --merged <default>` に出る → 通常マージ済み → `git branch -d <branch>`
   - 出ないものは squash マージの可能性 → `gh pr view <branch> --json state -q .state` が `MERGED` → `git branch -D <branch>` で削除可（根拠を報告に残す）
   - PR が OPEN / 存在しない / 未 push → **削除せず報告のみ**
7. worktree の後片付け: `git worktree list` で削除対象ブランチの worktree があれば `git worktree remove <path>`（dirty なら停止して報告）
8. 報告: 削除したブランチ一覧（各行に根拠: merged / PR MERGED）と、残したブランチとその理由

## 安全規則

- `-D` の使用は「`gh pr view` で state=MERGED を確認できた場合」のみ。それ以外の未マージブランチに `-D` を使わない
- デフォルトブランチ・現在のブランチは削除しない
- リモートブランチの削除は明示的に依頼された場合のみ（GitHub 側の自動削除設定が既定）
- `git reset` / `git checkout -- .` / stash の破棄は行わない（このスキルの守備範囲外）

## よくある失敗

| 症状 | 原因と対処 |
|------|-----------|
| `--merged` に出ないので削除をスキップされた | squash マージ。手順 6 の `gh pr view` 判定を必ず実施 |
| `error: branch not fully merged` | 未マージ。`-D` にエスカレートせず報告して判断を仰ぐ |
| worktree remove が拒否される | worktree が dirty。中身を報告し、ユーザー判断を待つ |
