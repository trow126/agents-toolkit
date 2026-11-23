---
name: gh-finish
description: Verifies a finished Issue; --apply commits, merges locally, and closes it in one explicit request. Use when the user says an Issue is done and asks to finish it without a PR（「Issue#Nが完了したよ」等）. Not for opening a PR, a generic commit (git-operations), or branch-cleanup.
argument-hint: "<issue-number> [--apply]"
---

# /gh-finish

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Modes

- `/gh-finish <issue>`: verify the implementation against the Issue (tests, diff review) and preview the exact commit, merge, and close operations; no writes.
- `/gh-finish <issue> --apply`: after a passing verification, perform the previewed sequence — commit the Issue-scoped changes, locally merge the feature branch into the default branch, and close the Issue with a completion comment.

`--apply` is the single explicit request covering exactly those three side effects. Neither mode ever pushes, creates a PR, deletes branches, or touches unrelated changes.

## Required behavior

1. Verify Issue number, repository, feature branch, and which working-tree changes belong to the Issue; unrelated changes are left untouched, but stop both modes if they overlap Issue-scoped files or would block branch checkout or merge.
2. Fetch the Issue via `~/.claude/bin/gh-issue-fetch.sh`; check every acceptance criterion / checkbox against actual code and test evidence, not the conversation or checkbox tick state; an item lacking evidence is a gap, reported in both modes (preview is then marked not ready to apply), and it stops `--apply`.
3. Run the project's deterministic verification (at minimum tests and lint for the affected scope per `references/workflow.md`, plus any project-defined typecheck/build; report if none can be run). A failing or unrunnable check stops both modes — report, never merge over a failure.
4. In `--apply`, stage only Issue-scoped paths, use Conventional Commits, fast-forward or no-ff merge per repo convention, and close via one `gh issue close --comment` citing the evidence.
5. Leave the merged feature branch in place; cleanup is a separate `/branch-cleanup` request.
6. Report each operation performed, skipped (writes omitted in preview, or already-done steps that are not stop conditions, e.g. committing when the changes are already committed), or halted by a stop condition, with the evidence or reason, and list the exact remaining manual steps (push is always one when verification passes).
