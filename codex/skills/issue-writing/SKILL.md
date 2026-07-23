---
name: issue-writing
description: Use when creating or updating a GitHub Issue body, drafting a new issue, or rewriting a follow-up issue so it matches the repo's issue template, exact headings, and verification standards. Do not use for issue comments, labels, assignees, or PR descriptions.
---

# Issue Writing

Use this skill whenever Codex is asked to create or update a GitHub Issue body.
The goal is that the next implementer or reviewer does not need to guess what
work remains.

## Scope

Use this skill for:

- New GitHub Issues
- Existing GitHub Issue body updates
- Follow-up Issues spun out from an earlier Issue or PR
- Offline drafts that will later become an Issue body

Do not use this skill for:

- Issue comments
- PR titles or PR descriptions
- Label, assignee, milestone, or project-board changes

## Workflow

### 1. Classify the Issue first

Classify the work as exactly one of:

- `implementation`
- `bug/fix`
- `investigation/review/validation`
- `retrospective`
- `backlog/umbrella`

If updating an existing Issue, preserve the current type unless the body clearly
shows it was structured as the wrong kind of Issue.

### 2. Find the source of truth for headings

Check for templates in this order:

1. The target repository's `.github/ISSUE_TEMPLATE/`
2. `$HOME/.github/ISSUE_TEMPLATE/`

When creating or updating through CLI or API, manually reproduce the exact
heading labels from the chosen template in the Issue body. Do not rely on
GitHub form enforcement.

If you need a Markdown starter for CLI/API editing, begin from the closest
manual skeleton under `$HOME/.github/ISSUE_TEMPLATE/manual/`, then add
or adjust any headings required by the chosen template.

Use this mapping when selecting the closest template:

- `implementation` -> `feature.yml` or `manual/implementation.md`
- `bug/fix` -> `bug.yml` or `manual/bug_fix.md`
- `investigation/review/validation` -> `task.yml` or `manual/investigation_validation.md`
- `retrospective` -> `retrospective.yml` or `manual/retrospective.md`
- `backlog/umbrella` -> `backlog.yml` or `manual/backlog_umbrella.md`

### 3. Preserve the exact headings

Use the exact heading names from the chosen template. Do not rename them to
informal alternatives such as `背景`, `問題`, `やること`, `受け入れ条件`, or
`関連`.

If the chosen issue form includes fields like these, reproduce them explicitly
in CLI/API-created or updated bodies:

- `Implementation kind / 実装種別`
- `Work kind / 作業種別`

If a required section is intentionally empty, write `None`. Add a short reason
when that avoids ambiguity.

### 4. Draft or normalize the body

For new Issues:

- Fill every required section concretely.
- State the target explicitly: repository, file, module, function, workflow,
  run, dataset, or milestone as applicable.
- State what is still wrong, missing, or incomplete in concrete terms.
- State what should change. If work is limited to known files or functions,
  enumerate each one explicitly.
- State what is out of scope when ambiguity is possible.

For existing Issue updates:

- Read the current body first.
- Preserve still-valid facts, links, logs, evidence, reproduction details, and
  related context.
- Rewrite the body under canonical headings when the existing structure is
  informal or incomplete.
- Restate the current remaining work directly instead of relying on earlier
  discussion, prior Issues, or PR comments.
- Avoid unrelated rewrites outside the requested scope.

### 5. Apply type-specific requirements

For `implementation` and `bug/fix` Issues:

- Make the remaining problem actionable enough that an implementer does not
  need to guess what remains.
- Include concrete required changes, explicit non-goals, closure criteria, and
  verification commands.
- For `bug/fix`, include reproduction steps, expected behavior, and environment
  details when relevant.

For `investigation/review/validation` Issues:

- Say explicitly that code changes are not the primary goal.
- Define the question or hypothesis and the expected output.
- Include completion criteria plus verification or reproduction details.

For `retrospective` Issues:

- Record the exact date, time window, run window, or incident window.
- Separate facts and evidence from interpretation.
- Define the follow-up path and the close condition.

For `backlog/umbrella` Issues:

- State that the Issue coordinates other work.
- List child Issues or concrete child work items explicitly.
- Define exactly when the umbrella can be closed.

### 6. Reject vague phrasing

Do not leave wording like `clean up`, `align`, `finish`, or `address remaining
items` unless the exact remaining items are listed in the body.

If the Issue is a follow-up to an earlier Issue or PR, restate the concrete
remaining work in the current Issue body instead of pointing back to earlier
discussion as the main source of truth.

## Final checklist

Before you submit or hand back the Issue body, verify that:

- The Issue type matches one of the allowed categories.
- The body uses the chosen template's exact headings.
- All required sections are present.
- The target is explicit.
- The remaining problem and required changes are concrete.
- Non-goals and close conditions are stated when applicable.
- Verification commands or reproduction details are present when the work
  should be tested, validated, or reproduced.
- Empty required sections use `None` rather than being omitted.
- Relevant existing evidence or context was preserved during updates.

## Issue Completeness Policy（共有正本）

Repo 固有の `.github/ISSUE_TEMPLATE` がある場合はその見出し・必須フィールドが正確な source of truth。本ポリシーはそれを置き換えず、完全性要件を上乗せする。

<!-- 正本: ~/.agents/rules/issue-completeness.md（編集は正本側で行い、~/.agents/bin/sync-shared-rules.sh --write で同期する） -->
<!-- BEGIN shared:issue-completeness -->
## Issue Completeness Policy

## Purpose

Prevent predictable follow-up issues that exist only because the initial issue
did not define the real completion state. The first issue should normally be
self-contained enough that an implementer can decide done or not-done without
guessing what "complete" means.

## Core Rules

1. Initial issue completeness is the default requirement.
   - Write the first issue so it can stand on its own.
   - Do not leave essential completion logic, artifact integrity conditions, or
     known edge cases for a predictable follow-up issue.

2. Define success by final state, not intermediate signals.
   - Success criteria must be based on final persisted state or user-visible
     outcome.
   - Do not treat a function return value, temporary in-memory result, or
     transient `exit 0` as sufficient unless that is also the real final
     outcome.

3. Review completeness before posting the issue.
   - When relevant to the task, explicitly check whether the issue addresses:
     - normal success
     - partial success
     - zero-result or empty-result cases
     - incremental or append-to-existing-data success
     - precondition failure
     - retry and idempotency
     - stale artifact or stale state
     - operator-visible success signals versus actual persisted data state

4. Require concrete, closeable issue bodies.
   - The issue must make the concrete problem explicit.
   - The issue must state the exact target: repository, file, module,
     function, workflow, dataset, artifact, or run.
   - The issue must state the intended outcome.
   - The issue must state what remains wrong or incomplete.
   - The issue must state what must change.
   - The issue must state non-goals when ambiguity is possible.
   - The issue must state completion or acceptance criteria that can decide
     whether the issue can be closed.
   - The issue must state verification steps or commands when validation or
     reproduction is expected.

5. Follow-up issues are restricted.
   - Open a follow-up issue only when genuinely new information appears after
     the original issue was created and that information was not reasonably
     foreseeable at issue creation time.
   - If the missing requirement was predictable, treat it as an initial issue
     quality failure rather than as justification for issue splitting.

## Quality Gate

Before posting or closing issue design work, ask:

`Can the implementer decide completion from this one issue alone?`

If the answer is no, the issue is incomplete and should be revised before work
continues.

## Guidance By Task Shape

- Persistence, scraping, backfill, settlement, CLI, migration, and generated
  artifact tasks require special care because real completion depends on saved
  outputs or operator-visible behavior.
- For those tasks, the issue should normally describe the expected post-save or
  externally visible state, not only the execution path.
- If partial save is allowed, the issue must distinguish between "data may be
  saved" and "task is considered successful."
<!-- END shared:issue-completeness -->
