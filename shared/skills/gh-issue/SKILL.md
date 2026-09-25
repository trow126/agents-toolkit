---
name: gh-issue
description: Creates or closes one GitHub Issue per request, or drafts an Issue retrospective. Use when the user explicitly asks to create or close an Issue or to write a retrospective. Not for drafting or rewriting the Issue body (issue-writing).
argument-hint: "create <body-file> | close <number> | retro <number> [--apply <path>]"
---

# gh-issue

Invoked as `/gh-issue` in Claude Code and `$gh-issue` in Codex.

**Stop** before any GitHub write other than the one the mode names. **Done** when that write is confirmed, or when the retrospective is returned (or written to the `--apply` path).

Read [`references/workflow.md`](references/workflow.md). For create or body updates, also use the installed `issue-writing` skill.

- `create <body-file>` validates and creates one Issue.
- `close <number>` verifies close criteria and closes one Issue.
- `retro <number>` produces an in-chat retrospective only.
- `retro <number> --apply <path>` writes the reviewed retrospective to that exact repo-local path.

Prefer the GitHub connector and preserve approval for create/close. Never infer labels, project updates, comments, learning promotion, file deletion, or memory changes from these modes.
