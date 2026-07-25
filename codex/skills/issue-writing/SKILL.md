---
name: issue-writing
description: Use when creating or updating a GitHub Issue body, drafting a new Issue, or rewriting a follow-up Issue to match the repository template and verification standard. Do not use for comments, labels, assignees, projects, or PR descriptions.
---

# Issue Writing

Read `~/.agents/rules/issue-completeness.md` before drafting.

1. Classify the Issue as `implementation`, `bug/fix`, `investigation/review/validation`, `retrospective`, or `backlog/umbrella`.
2. Read the existing body when updating. Locate templates in the target repository first, then `$HOME/.github/ISSUE_TEMPLATE/`; their exact headings and required fields are authoritative.
3. For CLI/API use, reproduce the selected form headings manually and start from the closest `$HOME/.github/ISSUE_TEMPLATE/manual/` skeleton when available.
4. Preserve valid facts, evidence, links, reproduction details, and context. State the exact target, remaining problem, required changes, non-goals, completion criteria, and verification.
5. For bug/fix include reproduction, expected behavior, and relevant environment. For investigation define the question and expected output. For retrospective separate facts from interpretation. For umbrella Issues enumerate child work and close conditions.
6. Use `None` for intentionally empty required sections. Reject vague phrases unless the exact remaining work follows.
7. Before submission, verify that one Issue is sufficient for an implementer to decide completion and that success describes final persisted or user-visible state.

Drafting does not authorize creating or updating the Issue. The corresponding GitHub write remains a separate approved action.
