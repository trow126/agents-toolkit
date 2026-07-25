# gh-review workflow

## Local review-fix mode

1. Validate the PR identifier, repository, current branch, worktree, and authentication.
2. Gather PR metadata, checks, unresolved threads, inline comments, top-level reviews, and automated review sources. Prefer the GitHub connector; use GraphQL where thread state matters.
3. Normalize duplicates and classify each finding as actionable, already fixed, invalid, out of scope, or requiring user judgment.
4. For actionable findings, inspect the actual code and reproduce the problem before editing when practical.
5. Apply scoped fixes and corresponding tests. Never disable a test, weaken secret/security detection, or accept a suggestion solely because a reviewer proposed it.
6. Run affected tests and summarize local results. Stop without commit, push, comments, or thread resolution.

## Commit follow-up

`--commit` rechecks the diff and tests, stages only review-fix paths, and creates semantic commits. It never pushes or writes GitHub state.

## Push follow-up

`--push` requires a clean feature branch whose intended commits already exist. It pushes only that branch and never comments or resolves threads.

## Comment follow-up

`--comment` uses current evidence to post or resolve one response per GitHub write approval. A response identifies the finding, disposition, evidence, and commit when applicable. It never edits, commits, or pushes.

## Stop conditions

- Invalid/combined modes, missing PR, wrong branch, unresolved merge/rebase, or overlapping user changes.
- Incomplete review context that prevents confident classification.
- Failing tests or high-impact reviewer advice requiring a product/security decision.
- Any failed external write; do not silently retry or mark a thread resolved.
