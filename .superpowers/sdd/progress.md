# agents-toolkit モノレポ移行 進捗レジャー

計画: claudedocs/2026-07-13-agents-toolkit-monorepo-migration-plan.md
ブランチ: docs/agents-toolkit-monorepo-design(計画・設計ドキュメント)

- Task 1: complete (git 管理外 ~/.agents/bin/sync-shared-rules.sh の mv→cp+rm 修正、冪等性検証済み、review approved)
- Task 2: complete (機微監査。決定: AGENTS.md 2行汎用化済み・default.rules 追跡除外・agmsg db/run/teams 除外。計画 gitignore へ反映済み commit 4c4a389)
- Task 3: complete (キット4ファイル作成。初回レビュー Needs fixes → 7修正+1反証(pgrep実証) → 再レビュー Approved。commit 2421000 で計画側も修正済み)
- Minor findings 記録(最終レビューでトリアージ):
  - rm -f のサイレント性(Task 1、ブリーフ指定どおりのため対応不要と判断)
  - trap ERR メッセージにロールバックコマンドをインライン表示せず計画参照のみ(Task 3 再レビュー)
  - broken symlink 名 claude の edge case は -e で検出不可(Task 3 再レビュー、trap で捕捉される)
- 次: Task 4(merge → push → gh rename → remote URL)。rename はユーザー確認後に実行
