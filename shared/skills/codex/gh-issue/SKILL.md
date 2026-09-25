---
name: gh-issue
description: Creates or closes one GitHub Issue per request, or drafts an Issue retrospective. Use when the user explicitly asks to create or close an Issue or to write a retrospective. Not for drafting or rewriting the Issue body (issue-writing).
argument-hint: "create <body-file> | close <number> | retro <number> [--apply <path>]"
---

# $gh-issue

Read [`../../gh-issue/references/workflow.md`](../../gh-issue/references/workflow.md). For create or body updates, also use the installed `issue-writing` skill.

- `create <body-file>` validates and creates one Issue.
- `close <number>` verifies close criteria and closes one Issue.
- `retro <number>` produces an in-chat retrospective only.
- `retro <number> --apply <path>` writes the reviewed retrospective to that exact repo-local path.

Use the GitHub connector and preserve approval for create/close. Never infer labels, project updates, comments, learning promotion, file deletion, or memory changes from these modes.
