---
name: gh-pr
description: Prepares, pushes, or creates a PR, or posts one review comment, each write in its own explicit mode. Use when the user asks to open a PR or post a PR review comment. Not for applying review feedback (gh-review).
argument-hint: "[base-branch] [--push|--create|--review-comment]"
---

# $gh-pr

Read [`../../gh-pr/references/workflow.md`](../../gh-pr/references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Modes

- `$gh-pr [base]`: validate the branch and prepare the exact title/body; no writes.
- `$gh-pr [base] --push`: push the current clean feature branch only.
- `$gh-pr [base] --create`: create one PR from an already pushed branch.
- `$gh-pr [base] --review-comment`: run post-PR review and post one review comment.

Modes are mutually exclusive. Invocation never creates a branch, stages files, commits dirty changes, or fixes review findings.

## Gates

Require a clean worktree, a non-`main`/`master` feature branch, existing commits ahead of the base, and no conflicting existing PR. Fail loudly on missing base/remote/authentication or rejected push.

PR creation and comments are distinct GitHub writes. Use the GitHub connector and retain its approval; `gh` fallback does not broaden authorization. After a review comment, report findings and stop until a separate `gh-review` request.
