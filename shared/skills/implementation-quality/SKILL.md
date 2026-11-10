---
name: implementation-quality
description: Loads only the relevant test, error-handling, diagnosis, hygiene, and language rules for a change. Use when implementing, fixing, refactoring, or reviewing code. Not for Git (git-operations).
---

# Implementation Quality

Use the smallest relevant rule set:

| Situation | Read before acting |
|---|---|
| Any code implementation, fix, refactor, or review | `~/.agents/rules/test-policy.md` |
| The task creates files, tests, scripts, or build artifacts | `~/.agents/rules/workspace-hygiene.md` |
| Diagnosing a failure or bug | `~/.agents/rules/failure-investigation.md` |
| Python is in scope | `~/.agents/rules/python-guidelines.md` |
| Markdown is edited | `~/.agents/rules/markdown-rules.md` |
| A recurring environment or CLI failure is directly relevant | `~/.agents/rules/learnings.md` |

Before the first write, send one line that starts with "Success condition:" and continue in the same turn without waiting for a reply. A description of what will be built is not a success condition.

In the same message, list the files you expect to change (specific paths, no globs or directories). At the end, compare that list with `git status --porcelain` and `git diff --stat`: report every changed path that was not declared, each with its reason, or revert it; say so explicitly when there is none. This is the declared-scope check against the diff (https://alexcloudstar.com/blog/ai-agent-pull-request-review-policy-2026/).

Inspect the surrounding implementation and tests. Keep the change scoped and implement the complete requested behavior. Write code that raises or exits non-zero when a required input or invariant is missing, with no silent fallback. When the task itself lacks a required input, stop and report what is missing.

After editing, run the narrowest deterministic checks that prove the behavior, then the repository gates required by the affected surface. Report executed checks and any remaining unverified item.

Do commit, merge, push, PR creation, writes to GitHub or other remote services, updates to memory, shared rules or learnings files, and deletion of files that existed before this task only when the user asked for that action in this task; loading this skill is not such a request. Running local tests, linters and builds needs no approval.
