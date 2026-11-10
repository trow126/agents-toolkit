---
name: git-operations
description: Inspects, stages, commits, branches, merges, or pushes Git state. Use for a generic Git request that no dedicated workflow covers. Not for gh-finish or branch-cleanup.
---

# Git Operations

Read `~/.agents/rules/git-workflow.md` before a mutating Git operation (any mode other than `default`), at step 2 when the mode is resolved; inspection in `default` mode does not load it.

Use one explicit mode per request: `default` (inspect), `stage`, `branch`, `commit`, `merge`, or `push`. A mode authorizes only the matching operation in `~/agents-toolkit/docs/contracts/skill-authority.tsv`; do not chain modes by implication: authorization for one operation does not authorize commit, merge, push, remote or repository creation (`git remote add`, `gh repo create`), PR creation, or cleanup.

1. Inspect `git status --short --branch`, the current branch, relevant diff, and divergence.
2. Resolve the exact operation the user requested and its mode. For any mode other than `default`, do the read named above now, before step 3.
3. Before staging, show the diff of every path you will stage (for untracked files, their content). Run this in its own command and read the output before staging; the managed pre-bash hook blocks `git add`/`commit`/`merge`/`push` and `gh repo create` chained with any other command, so use `git -C <dir>` instead of `cd <dir> &&`. `--stat`, `--summary`, a line count (`wc -l`), and output cut with `head` or `tail` do not count as review; show each untracked file's content, one file at a time. Preserve unrelated changes and stashes.
4. Before each mutation, run its preview form in a separate command and show the output: `git add --dry-run <paths>`, `git commit --dry-run --short`, `git merge-tree --write-tree HEAD <branch>` with `git log --oneline HEAD..<branch>` for a merge, `git push --dry-run --porcelain <remote> <ref>`. Proceed only if the previewed paths are exactly the paths reviewed in step 3 and the refs are the operation target resolved in step 2; stop when the preview shows a path that was not reviewed. A preview covers only the one mutation that follows it, so run `git commit --dry-run --short` again before every further commit.
5. Use a feature branch; never force-push `main` or `master`. Prefer `--ff-only` for local integration unless instructed otherwise.
6. Use non-interactive commands and fail on conflicts, missing remotes (report and stop; do not create one), ambiguous targets, or uncommitted changes that the requested mode would need committed first (stop, name the files, and ask; do not commit to satisfy a merge, push, or deploy request until the user answers that question by asking for the commit, and then commit only the named files in `commit` mode) instead of guessing.
7. Report the resulting branch, commit/divergence state, and operations not performed.

Dedicated skills (gh-finish, branch-cleanup) own their command-specific interfaces; the authority rows in `skill-authority.tsv` still apply to them.
