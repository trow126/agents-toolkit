## Git ワークフロー

- セッション開始時に `git status` と `git branch` を確認する
- すべての作業は feature ブランチで行い、main/master で直接作業しない
- 明示的な依頼なしにコミットしない。依頼されたコミットは意味単位で分割する
- ステージング前に必ず `git diff` を確認する
- リスクのある操作の前にロールバック手段（コミットの提案・バックアップ）を確保する
- Conventional Commits 形式 (fix:, feat:, docs: など) と説明的な本文を使用する
- "fix bug"、"update code"、"changes" のような曖昧なメッセージは避ける
