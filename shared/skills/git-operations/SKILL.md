---
name: git-operations
description: Inspects, stages, commits, branches, merges, or pushes Git state. Use for a generic Git request that no dedicated workflow covers. Not for gh-finish or branch-cleanup.
---

# Git Operations

Read `~/.agents/rules/git-workflow.md` before a mutating Git operation (any mode other than `default`); inspection in `default` mode does not load it.

Use one explicit mode per request: `default` (inspect), `stage`, `branch`, `commit`, `merge`, or `push`. A mode authorizes only the matching operation in `~/agents-toolkit/docs/contracts/skill-authority.tsv`; do not chain modes by implication: authorization for one operation does not authorize commit, merge, push, remote or repository creation (`git remote add`, `gh repo create`), PR creation, or cleanup.

1. Inspect `git status --short --branch`, the current branch, relevant diff, and divergence.
2. Resolve the exact operation the user requested.
3. Before staging, show the diff of every path you will stage (for untracked files, their content). Run this in its own command and read the output before staging; the managed pre-bash hook blocks `git add`/`commit`/`merge`/`push` and `gh repo create` chained with any other command, so use `git -C <dir>` instead of `cd <dir> &&`. A `--stat` or `--summary` alone does not count as review. Preserve unrelated changes and stashes.
4. Before each mutation, run its preview form in a separate command, show the output, and proceed only if the previewed paths and refs match what the user named: `git add --dry-run <paths>`, `git commit --dry-run --short`, `git merge-tree --write-tree HEAD <branch>` with `git log --oneline HEAD..<branch>` for a merge, `git push --dry-run --porcelain <remote> <ref>`.
5. Use a feature branch; never force-push `main` or `master`. Prefer `--ff-only` for local integration unless instructed otherwise.
6. Use non-interactive commands and fail on conflicts, missing remotes (report and stop; do not create one), ambiguous targets, or uncommitted changes that the requested mode would need committed first (stop, name the files, and ask; never commit to satisfy a merge, push, or deploy request) instead of guessing.
7. Report the resulting branch, commit/divergence state, and operations not performed.

Dedicated skills (gh-finish, branch-cleanup) own their command-specific interfaces; the authority rows in `skill-authority.tsv` still apply to them.
