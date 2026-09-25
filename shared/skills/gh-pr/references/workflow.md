# gh-pr workflow

## Preparation

1. Reject unknown or combined modes.
2. Inspect branch, status, remotes, base candidates, divergence, commits, and any existing PR.
3. Require a clean feature branch with at least one commit ahead of the selected base.
4. Summarize the complete commit diff and tests without inventing results.
5. Prepare a concise title and body containing summary, verification, risks, and Issue links.

## Push

`--push` performs only `git push -u origin <current-branch>` after rechecking the preparation gates. A rejected or authentication-failed push is reported unchanged; no pull/rebase is inferred.

## Create

`--create` requires the branch to be present on the remote and no existing open PR. Create one PR using the prepared body. Do not retry a failed create automatically because duplicate PRs are externally visible.

## Review comment

`--review-comment` requires an existing PR. Review the complete PR diff in an independent context, format actionable findings, and post one comment. Do not edit files or create follow-up commits in this mode.

1. Resolve the PR number and read the complete diff.
2. Produce findings in an independent context: Claude Code uses `/code-review <PR番号>`; Codex uses `codex review --base <base-branch>`. Review for bugs, security, performance, readability, and missing tests; read the project's `claudedocs/learnings.md` when present. Use the review output only as comment text, never as a repair plan.
3. Post exactly one comment with the template below.
4. Report that unresolved findings remain when they do, then stop until `gh-review` or another explicit user request.

Comment template (title is fixed to `Automated Code Review`):

```markdown
## Automated Code Review

### 概要
（変更内容の客観的な要約。1-2文）

### 要修正
| Severity | 箇所 | 問題 | 推奨対応 |
|----------|------|------|----------|
（バグ、セキュリティ、データ破損リスクなど。なければ「なし」）

### 改善提案
| 箇所 | 提案 | 理由 |
|------|------|------|
（パフォーマンス、可読性、保守性の改善。任意採用）

### 確認事項
- （レビュアーだけでは判断できない設計意図やビジネスロジックの確認）
```

The comment lists only unresolved findings, has no praise section, and does not pre-empt the author's replies about rejected findings.

## Stop conditions

- Dirty tree, detached HEAD, `main`/`master`, zero commits, missing base/remote, or ambiguous target.
- Existing PR when creating, absent PR when commenting, or any failed external operation.
- Any attempt to combine push, create, comment, commit, or repair into one authorization.
