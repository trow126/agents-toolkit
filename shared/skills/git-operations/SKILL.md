---
name: git-operations
description: Use for generic requests to inspect, stage, commit, branch, merge, or push Git state. Do not use when gh-start, gh-pr, gh-review, branch-cleanup, or another dedicated workflow skill applies.
---

# Git Operations

Read `~/.agents/rules/git-workflow.md` before a mutating Git operation.

Use one explicit mode per request: `default` (inspect), `stage`, `branch`, `commit`, `merge`, or `push`. A mode authorizes only the matching operation in `docs/contracts/skill-authority.tsv`; do not chain modes by implication.

1. Inspect `git status --short --branch`, the current branch, relevant diff, and divergence.
2. Resolve the exact operation the user requested. Authorization for one operation does not authorize commit, merge, push, PR creation, or cleanup as a group.
3. Before staging or committing, show and review the scoped diff. Preserve unrelated changes and stashes.
4. Use a feature branch; never force-push `main` or `master`. Prefer `--ff-only` for local integration unless instructed otherwise.
5. Use non-interactive commands and fail on conflicts, missing remotes, dirty scope, or ambiguous targets instead of guessing.
6. Report the resulting branch, commit/divergence state, and operations not performed.

Dedicated GitHub skills own their command-specific interfaces and override this generic router.
