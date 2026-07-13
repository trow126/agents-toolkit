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
2. `/home/trow126/.github/ISSUE_TEMPLATE/`

When creating or updating through CLI or API, manually reproduce the exact
heading labels from the chosen template in the Issue body. Do not rely on
GitHub form enforcement.

If you need a Markdown starter for CLI/API editing, begin from the closest
manual skeleton under `/home/trow126/.github/ISSUE_TEMPLATE/manual/`, then add
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
