---
name: gh-review
description: Use when the user asks Claude Code to address actionable review feedback on an existing PR. Default mode applies local fixes and tests only; commit, push, and GitHub responses require separate explicit modes. Do not use for creating a PR.
argument-hint: "<pr-number> [--commit|--push|--comment]"
---

# /gh-review

Read [`../../gh-review/references/workflow.md`](../../gh-review/references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Modes

- `/gh-review <PR>`: collect all review sources, classify findings, implement valid local fixes, and test.
- `/gh-review <PR> --commit`: commit already verified review fixes only.
- `/gh-review <PR> --push`: push the current committed feature branch only.
- `/gh-review <PR> --comment`: post or resolve one review response per approved GitHub write.

Modes are mutually exclusive follow-ups. Default mode does not commit, push, comment, or resolve threads.

Preserve unrelated changes, reproduce valid defects before fixing when practical, and reject suggestions that weaken security or tests. Report accepted, rejected, duplicate, and unresolved findings with evidence.
