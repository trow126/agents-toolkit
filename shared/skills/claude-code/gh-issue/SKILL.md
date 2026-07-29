---
name: gh-issue
description: Use when the user explicitly asks Claude Code to create or close a GitHub Issue, or to draft a retrospective. Each create/close is one GitHub write; retrospective application is a separate local-file action. Do not auto-delete brainstorms, checkpoints, or memory.
argument-hint: "create <body-file> | close <number> | retro <number> [--apply <path>]"
---

# /gh-issue

Read [`references/workflow.md`](references/workflow.md). For create or body updates, also use the installed `issue-writing` skill.

- `create <body-file>` validates and creates one Issue.
- `close <number>` verifies close criteria and closes one Issue.
- `retro <number>` produces an in-chat retrospective only.
- `retro <number> --apply <path>` writes the reviewed retrospective to that exact repo-local path.

Prefer the GitHub connector and preserve approval for create/close. Never infer labels, project updates, comments, learning promotion, file deletion, or memory changes from these modes.
