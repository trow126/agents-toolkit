# gh-finish workflow

## Verification gate (both modes)

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository, a non-`main`/`master` feature branch, and no unresolved merge/rebase state.
3. Fetch the Issue through the bundled structured helper; fail on missing Issue. An already-closed Issue stops `--apply`.
4. Map every acceptance criterion and checkbox in the Issue body to concrete evidence: code paths, test names, run output. An item with no code or test evidence is a gap and stops `--apply`. The tick state of a checkbox in the Issue body is not evidence: an unticked box with evidence passes, a ticked box without evidence is a gap.
5. Run the project's tests and lint for the affected scope. Failures stop both modes with the output shown.
6. Confirm the diff contains only Issue-attributable changes. Overlapping unrelated changes are never staged; report and stop.

## Preview (default mode)

Show, without executing: the paths to stage, the Conventional Commit message(s) (split by concern here when the diff spans distinct changes), the merge command (target branch and ff/no-ff choice per repo convention), and the `gh issue close --comment` text. End by naming `--apply` as the follow-up.

## Apply mode

1. Stage only the previewed paths and create exactly the previewed commits. Decide any split by concern in the preview, never at apply time.
2. Check out the default branch, merge the feature branch locally, and return any pre-existing state faithfully. On merge conflict: abort the merge, restore the branch state, report — never resolve conflicts silently inside this skill.
3. Close the Issue with exactly one `gh issue close --comment` citing the default-branch commit that contains the change (the merge commit for --no-ff, the fast-forwarded tip for ff), the feature commit(s), and test evidence. Prefer the GitHub connector; `gh` fallback does not broaden authorization.
4. Do not push. Always list the exact push command in the report as a remaining manual step; pushing takes a separate user request.

## Stop conditions

- Missing repository, Issue, helper, or authentication.
- Failing tests/lint, unverifiable acceptance criteria, or unrelated dirty changes overlapping the scope.
- Merge conflicts, detached HEAD, or a default branch that has diverged in a way the user has not acknowledged.
- A request to run `git push`, `gh pr create`, `git branch -d`/`-D`, `git stash`, `git tag`, or any commit outside the previewed set as part of this skill.
