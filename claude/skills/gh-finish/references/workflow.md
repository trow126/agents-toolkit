# gh-finish workflow

## Verification gate (both modes)

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository, a non-`main`/`master` feature branch (not a detached HEAD), and no unresolved merge/rebase state.
3. Fetch the Issue through the structured helper `~/.claude/bin/gh-issue-fetch.sh`; fail on missing Issue. An already-closed Issue is reported in both modes and stops `--apply`.
4. Map every acceptance criterion and checkbox in the Issue body to concrete evidence: code paths, test names, run output. An item with no code or test evidence is a gap: report it in both modes and stop `--apply`. The tick state of a checkbox in the Issue body is not evidence: an unticked box with evidence passes, a ticked box without evidence is a gap.
5. Run the project's tests and lint for the affected scope, plus any project-defined typecheck/build. Failing or unrunnable checks stop both modes with the output shown.
6. Identify which changes (working tree, index, and feature-branch commits) belong to the Issue. Unrelated uncommitted changes are left untouched and never staged; if unrelated changes overlap Issue-scoped files, are committed on the feature branch, or would block branch checkout or merge, report and stop (both modes).

## Preview (default mode)

Show, without executing: the paths to stage, the Conventional Commit message(s) (split by concern here when the diff spans distinct changes), the merge command (target branch and ff/no-ff choice per repo convention, judged in order: repo docs, `git config --local merge.ff`, merge history, `~/.agents/rules/git-workflow.md`, then Git's default ff-when-possible), and the `gh issue close --comment` text. If an acceptance-criteria gap or an already-closed Issue exists, mark the preview not ready to apply and state what blocks `--apply`; otherwise end by naming `--apply` as the follow-up.

## Apply mode

1. Stage only the previewed paths and create exactly the previewed commits (if the Issue changes are already committed, skip committing and report it as skipped). Decide any split by concern in the preview, never at apply time.
2. Check out the default branch, merge the feature branch locally, and return any pre-existing state faithfully. On merge conflict: abort the merge, check out the feature branch again, report — never resolve conflicts silently inside this skill.
3. Close the Issue with exactly one `gh issue close --comment` citing the default-branch commit that contains the change (the merge commit for --no-ff, the fast-forwarded tip for ff), the feature commit(s), and test evidence. Prefer the GitHub connector; `gh` fallback does not broaden authorization.
4. Do not push. When the local merge succeeds, always list the exact push command in the report as a remaining manual step; pushing takes a separate user request.

## Stop conditions

- Missing repository, Issue, helper, or authentication.
- Failing or unrunnable tests/lint/typecheck/build, or unrelated changes overlapping Issue-scoped files, committed on the feature branch, or blocking checkout/merge (both modes).
- Acceptance-criteria gaps or an already-closed Issue (`--apply` only; the preview reports them and is marked not ready to apply).
- Merge conflicts, detached HEAD, or a default branch that has diverged in a way the user has not acknowledged.
- A request to run `git push`, `gh pr create`, `git branch -d`/`-D`, `git stash`, `git tag`, or any commit outside the previewed set as part of this skill.
