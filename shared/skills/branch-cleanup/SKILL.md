---
name: branch-cleanup
description: Use when the user says a branch or PR was merged and asks to clean up（「マージしたからブランチを整理して」「リモートでマージしたからローカルを整理して」「ブランチの後片付け」等）, or when stale merged branches/worktrees remain after a PR merge.
allowed-tools: Bash
---

# Branch Cleanup

マージ済みブランチの後片付けを安全に定型実行する。squash マージ（`git branch --merged` に現れない）を正しく扱う。

## 手順

1. `git status --porcelain` を単独のコマンドとして実行し、出力を読む。出力が空でなければ**停止して報告**する（整理はしない）。手順 2 以降のコマンドを同じ Bash 呼び出しに `;` や `|` でつながない（つなぐ場合は `test -z "$(git status --porcelain)" &&` で始める）
2. デフォルトブランチを特定: `git remote show origin` の HEAD branch（通常 main または master）
3. デフォルトブランチへ切替: `git checkout <default>`
4. `git pull --ff-only`（失敗したら停止して報告する。merge・rebase・reset で解消しない）
5. `git fetch --prune`
6. ローカルブランチを分類し削除対象を決める（対象はユーザーが特定のブランチや PR を指定した場合は該当ブランチ（PR は head ブランチ）のみ、指定がなければ全ローカルブランチ。ただしデフォルトブランチは常に除外する。worktree に checkout 中のブランチも分類対象に含める）:
   - `git branch --merged <default>` に出る → 通常マージ済み → 削除対象（`git branch -d <branch>`）
   - 出ないものは squash / rebase マージの可能性 → 安全規則の `-D` 条件（独立した 2 つの根拠）を満たせば削除対象（`-d` を試さず直接 `git branch -D <branch>`）
   - `--merged` に出ず、安全規則の 2 つの根拠がそろわない → **削除せず報告のみ**（欠けた根拠を書く）
7. worktree の後片付けとブランチ削除: 手順 6 の削除対象について `git worktree list` を確認する。worktree がなければ手順 6 で決めたコマンド（`-d` または `-D`）で削除する。worktree があり clean なら `git worktree remove <path>` で外してから同様に削除する（worktree に checkout 中のブランチは外すまで削除できない）。dirty な worktree はその worktree とブランチだけを残し、`git status --porcelain` の要約を記録して残りの候補の処理を続ける
8. 報告（途中で残した項目があっても必ず行う）: 削除したブランチ一覧（各行に根拠: merged / PR MERGED + merge-tree 一致）と、残したブランチ・worktree とその理由

## 安全規則

- `-D` は出所の異なる 2 つの根拠が両方そろった場合のみ使い、両方を報告に残す。どちらか一方だけなら残して報告する
  - GitHub: `gh pr view <branch> --json state -q .state` が MERGED
  - ローカル: `git merge-tree --write-tree <default> <branch>` が exit 0 で、出力の tree が `git rev-parse <default>^{tree}` と一致する（ブランチを default に merge しても何も変わらない＝内容が取り込み済み）。merge 後にブランチへ足した commit があると一致しない。conflict や不一致なら残す。merge simulation による取り込み判定の既知手法（worktrunk: https://github.com/max-sixty/worktrunk/commit/6325be28）
- それ以外の未マージブランチに `-D` を使わない
- デフォルトブランチは削除しない。また、削除実行時点でいずれかの worktree に checkout されたままのブランチ（dirty な worktree に残したもの等）は削除しない（開始時にいたブランチは、手順 3 で default に切り替えた後は通常の候補として分類する）
- リモートブランチの削除は明示的に依頼された場合のみ。依頼時も、デフォルトブランチ以外で `origin/<branch>` が存在するもののうち、手順 6–7 で削除したローカルブランチに対応するもの、またはユーザーが明示指定したものだけを対象とする。対象は `origin/<branch>` 自体が `git branch -r --merged <default>` に出るか、2 つの根拠（`merge-tree` の対象は `origin/<branch>`）を満たす場合のみ `git push origin --delete <branch>` で削除し、報告に含める（満たさないものは削除せず報告する。マージ後の自動削除は repo ごとの設定で、既定は off。`gh api repos/{owner}/{repo} --jq .delete_branch_on_merge` で確認できる）
- `git reset` / `git checkout -- .` / stash の破棄は行わない（このスキルの守備範囲外）

## よくある失敗

| 症状 | 原因と対処 |
|------|-----------|
| `--merged <default>` に出たのに `-d` が `error: the branch '<branch>' is not fully merged` | `-d` は upstream を基準に判定する。upstream が残っていてローカル tip と異なる。両方の SHA を報告してブランチは残す |
| `--merged` に出ず 2 つの根拠もそろわないブランチで `error: the branch '<branch>' is not fully merged` | 手順 6 通りなら `-d` を実行しないため起きない。手順を逸脱して誤って `-d` を実行しこのエラーが出た場合も、`-D` にエスカレートせず未マージとして報告し判断を仰ぐ |
