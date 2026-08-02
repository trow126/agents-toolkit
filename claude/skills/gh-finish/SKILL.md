---
name: gh-finish
description: Use when the user says an Issue's implementation is done and asks to finish it without a PR（「Issue#Nが完了したよ」「コミット、ローカルマージ、クローズをお願い」等）. Default mode verifies and previews only; --apply performs commit → local merge → Issue close in one explicit request. Do not use for PR-based completion (use gh-pr) or branch deletion (use branch-cleanup).
argument-hint: "<issue-number> [--apply]"
---

# /gh-finish

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Modes

- `/gh-finish <issue>`: verify the implementation against the Issue (tests, diff review) and preview the exact commit, merge, and close operations; no writes.
- `/gh-finish <issue> --apply`: after a passing verification, perform the previewed sequence — commit the Issue-scoped changes, locally merge the feature branch into the default branch, and close the Issue with a completion comment.

`--apply` is the single explicit request covering exactly those three side effects. Neither mode ever pushes, creates a PR, deletes branches, or touches unrelated changes.

## Required behavior

1. Verify Issue number, repository, feature branch, and that the working diff is attributable to the Issue.
2. Fetch the Issue via `~/.claude/bin/gh-issue-fetch.sh`; check every acceptance criterion / checkbox against actual code and test evidence, not the conversation.
3. Run the project's deterministic verification. A failing check stops both modes — report, never merge over a failure.
4. In `--apply`, stage only Issue-scoped paths, use semantic Conventional Commits, fast-forward or no-ff merge per repo convention, and close via one `gh issue close --comment` citing the evidence.
5. Leave the merged feature branch in place; cleanup is a separate `/branch-cleanup` request.
6. Report each operation performed or skipped, with the evidence, and the exact remaining manual steps (e.g. push) if the user wants them.
