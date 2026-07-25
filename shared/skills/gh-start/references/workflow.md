# gh-start workflow

## Default implementation mode

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the current directory is the intended Git repository and the branch is neither `main` nor `master`.
3. Inspect `git status --short --branch`; unrelated or overlapping dirty changes are never staged, reset, or rewritten.
4. Fetch the Issue through the bundled structured helper. Fail on missing/closed Issue unless the user explicitly asked to continue closed work.
5. Translate the Issue into concrete local success criteria. If the body is ambiguous in a way that changes design or data, pause before editing.
6. Inspect the implementation, tests, and project instructions; apply the relevant implementation-quality rules.
7. Implement and test locally. Do not create commits, external updates, PRs, or persistent workflow state.
8. Report changed paths, verification results, remaining risk, and the separate follow-up command for any desired side effect.

## Commit follow-up

`--commit` requires a feature branch, a reviewed diff, passing relevant tests, and changes attributable to the Issue. It stages only those paths and creates semantic Conventional Commits. It never pushes or updates GitHub.

## Sync follow-up

`--sync` derives one concise status update from current diff and test evidence. Prefer the GitHub connector and preserve its per-write approval. If unavailable, show the exact `gh issue comment` operation and require this explicit mode before running it. It never edits, commits, or pushes.

## Stop conditions

- Missing repository, Issue, helper, authentication, or required project instruction.
- `main`/`master`, detached HEAD, unresolved merge/rebase, or overlapping user changes.
- Invalid or combined modes.
- Test failure whose cause is outside the authorized scope.
- Any request to infer commit, push, PR, or cleanup authority from another action.
