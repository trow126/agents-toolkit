---
name: issue-writing
description: Drafts or rewrites a GitHub Issue body to match the repository template, exact headings, and completion and verification standard. Use when creating or updating a GitHub Issue body（GitHub Issue の本文を作成・更新するとき）. Not for gh-issue writes or comments.
---

# Issue Writing

Read `~/.agents/rules/issue-completeness.md` before drafting.

Stop and ask when the target repository, the Issue type, or the concrete remaining work cannot be determined. The draft is complete when one Issue lets an implementer decide completion without guessing.

1. Classify the Issue as `implementation`, `bug/fix`, `investigation/review/validation`, `retrospective`, or `backlog/umbrella`.
2. Read the existing body when updating. Locate templates in the target repository first, then `$HOME/.github/ISSUE_TEMPLATE/`; their exact headings and required fields are authoritative. Without a matching template, use the minimum sections in `issue-completeness.md`.
3. For CLI/API use, form enforcement does not apply: reproduce the selected form headings manually and start from the closest `$HOME/.github/ISSUE_TEMPLATE/manual/` skeleton when available.
4. Use the exact heading names. Do not replace them with informal alternatives such as `背景`, `問題`, `やること`, `受け入れ条件`, or `関連`; put extra explanation under the canonical heading. Do not omit required sections; write `None` for an intentionally empty one and say why when that avoids ambiguity.
5. Preserve valid facts, evidence, links, reproduction details, and context. State the exact target (repository, file, module, function, or workflow), what is still wrong, what must change (enumerate each file or function when the remaining work is limited to known ones), non-goals, completion criteria, and verification steps or commands.
6. For a follow-up to an earlier Issue or PR, restate the concrete remaining work instead of relying on the prior discussion. Reject vague wording such as "clean up", "align", "finish", or "address remaining items" unless the exact items follow.
7. For bug/fix include reproduction, expected behavior, and relevant environment. For investigation, review, or validation, say explicitly that the output is not a code change and define the expected output. For a retrospective, record the date or run window, the observations and evidence, the interpretation, and the follow-up path, and never present it as an implementation Issue. For an umbrella, say that it coordinates other Issues, link each child Issue, and define when it can close; it never replaces the child Issues' details.
8. Before submission, verify that one Issue is sufficient for an implementer to decide completion and that success describes final persisted or user-visible state.

Drafting does not authorize creating or updating the Issue. The corresponding GitHub write remains a separate approved action.
