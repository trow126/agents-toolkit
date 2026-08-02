# gh-finish workflow

## Verification gate (both modes)

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository, a non-`main`/`master` feature branch, and no unresolved merge/rebase state.
3. Fetch the Issue through the bundled structured helper; fail on missing Issue. An already-closed Issue stops `--apply`.
4. Map every acceptance criterion and checkbox in the Issue body to concrete evidence: code paths, test names, run output. Unchecked or unverifiable items are reported as gaps and stop `--apply`.
5. Run the project's tests and lint for the affected scope. Failures stop both modes with the output shown.
6. Confirm the diff contains only Issue-attributable changes. Overlapping unrelated changes are never staged; report and stop.

## Preview (default mode)

Show, without executing: the paths to stage, the Conventional Commit message(s), the merge command (target branch and ff/no-ff choice per repo convention), and the `gh issue close --comment` text. End by naming `--apply` as the follow-up.

## Apply mode

1. Stage only the previewed paths; create the previewed commit(s) with semantic granularity（適切な粒度 — split by concern when the diff spans distinct changes）.
2. Check out the default branch, merge the feature branch locally, and return any pre-existing state faithfully. On merge conflict: abort the merge, restore the branch state, report — never resolve conflicts silently inside this skill.
3. Close the Issue with exactly one `gh issue close --comment` citing commit hash and test evidence. Prefer the GitHub connector; `gh` fallback does not broaden authorization.
4. No push at any point. If the user wants the merge pushed, name the exact command and require a separate request.

## Stop conditions

- Missing repository, Issue, helper, or authentication.
- Failing tests/lint, unverifiable acceptance criteria, or unrelated dirty changes overlapping the scope.
- Merge conflicts, detached HEAD, or a default branch that has diverged in a way the user has not acknowledged.
- Any request to infer push, PR, branch-deletion, or checkpoint authority from this skill.
