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
6. ローカルブランチを分類（除外対象は安全規則を参照）:
   - `git branch --merged <default>` に出る → 通常マージ済み → `git branch -d <branch>`
   - 出ないものは squash / rebase マージの可能性 → 安全規則の `-D` 条件（独立した 2 つの根拠）を満たせば `-d` を試さず直接 `git branch -D <branch>`
   - `--merged` に出ず、PR が OPEN / CLOSED（未マージ） / 存在しない / 未 push、または根拠が 1 つしかない → **削除せず報告のみ**（欠けた根拠を書く）
7. worktree の後片付け: `git worktree list` で削除対象ブランチの worktree があれば `git worktree remove <path>`。dirty な worktree はその worktree とブランチだけを残し、`git status --porcelain` の要約を記録して残りの候補の処理を続ける
8. 報告（途中で残した項目があっても必ず行う）: 削除したブランチ一覧（各行に根拠: merged / PR MERGED + merge-tree 一致）と、残したブランチ・worktree とその理由

## 安全規則

- `-D` は出所の異なる 2 つの根拠が両方そろった場合のみ使い、両方を報告に残す。どちらか一方だけなら残して報告する
  - GitHub: `gh pr view <branch> --json state -q .state` が MERGED
  - ローカル: `git merge-tree --write-tree <default> <branch>` が exit 0 で、出力の tree が `git rev-parse <default>^{tree}` と一致する（ブランチを default に merge しても何も変わらない＝内容が取り込み済み）。merge 後にブランチへ足した commit があると一致しない。conflict や不一致なら残す。merge simulation による取り込み判定の既知手法（worktrunk: https://github.com/max-sixty/worktrunk/commit/6325be28）
- それ以外の未マージブランチに `-D` を使わない
- デフォルトブランチ・現在のブランチは削除しない
- リモートブランチの削除は明示的に依頼された場合のみ（マージ後の自動削除は repo ごとの設定で、既定は off。`gh api repos/{owner}/{repo} --jq .delete_branch_on_merge` で確認できる）
- `git reset` / `git checkout -- .` / stash の破棄は行わない（このスキルの守備範囲外）

## よくある失敗

| 症状 | 原因と対処 |
|------|-----------|
| `--merged <default>` に出たのに `-d` が `error: the branch '<branch>' is not fully merged` | `-d` は upstream を基準に判定する。upstream が残っていてローカル tip と異なる。両方の SHA を報告してブランチは残す |
| `--merged` に出ず 2 つの根拠もそろわないブランチで `error: the branch '<branch>' is not fully merged` | 未マージ。`-D` にエスカレートせず報告して判断を仰ぐ |
