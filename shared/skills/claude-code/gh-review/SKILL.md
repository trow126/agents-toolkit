---
name: gh-review
description: Applies actionable PR review feedback as local fixes and tests; commit, push, and replies are separate explicit modes. Use when the user asks to address PR review comments. Not for reviewing (/code-review) or posting reviews (gh-pr --review-comment).
argument-hint: "<pr-number> [--commit|--push|--comment]"
---

# /gh-review

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Modes

- `/gh-review <PR>`: collect all review sources, classify findings, implement valid local fixes, and test.
- `/gh-review <PR> --commit`: commit already verified review fixes only.
- `/gh-review <PR> --push`: push the current committed feature branch only.
- `/gh-review <PR> --comment`: post or resolve one review response per approved GitHub write.

Modes are mutually exclusive follow-ups. Default mode does not commit, push, comment, or resolve threads.

Preserve unrelated changes, reproduce valid defects before fixing when practical, and reject suggestions that weaken security or tests. Report accepted, rejected, duplicate, and unresolved findings with evidence.
