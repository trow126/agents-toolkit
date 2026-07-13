# Git ワークフロールール

- セッション開始時に必ず `git status` と `git branch` を確認する
- すべての作業は feature ブランチで行い、main/master で直接作業しない
- 意味のあるメッセージで段階的にコミットする
- ステージング前に必ず `git diff` を確認する
- リスクのある操作の前にコミットしてロールバックに備える
- Conventional Commits 形式 (fix:, feat:, docs: など) と説明的な本文を使用する
- "fix bug"、"update code"、"changes" のような曖昧なメッセージは避ける
