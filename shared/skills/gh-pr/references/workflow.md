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

## Stop conditions

- Dirty tree, detached HEAD, `main`/`master`, zero commits, missing base/remote, or ambiguous target.
- Existing PR when creating, absent PR when commenting, or any failed external operation.
- Any attempt to combine push, create, comment, commit, or repair into one authorization.
