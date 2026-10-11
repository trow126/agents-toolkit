---
name: gh-index
description: Use for a read-only codebase survey that produces evidence for planning GitHub Issues. Default output stays in chat; --output writes the same reviewed index to one repo-local path. Do not edit code, create Issues, or update GitHub.
argument-hint: "[--output <path>] [--force]"
---

# gh-index

Read [`references/workflow.md`](references/workflow.md).

## Modes

- Default: inspect the repository and return the index in chat only.
- `--output <path>`: write the reviewed index to exactly one normalized path inside the current repository.
- `--force` is valid only with `--output` and explicitly authorizes overwriting that exact existing file.

Reject empty paths, repo-external paths, symlink escapes, unknown flags, or `--force` without `--output`. This skill never changes implementation files, creates Issues, commits, pushes, or writes external state.

The index must distinguish observed facts from hypotheses and contain enough target, dependency, risk, and verification detail to support later use of `issue-writing`.
