# Delegation prompt template

`~/.claude/bin/codex-delegate` renders this template from the contract JSON and passes it to
`codex exec` on stdin. Placeholders in braces are replaced; list values become bullet lists.
The profile `toolkit-implementer` repeats the constraints as developer instructions.

## Template

```text
Goal: {goal}

Acceptance criteria (all must hold when you finish):
{acceptance_criteria}

Scope: change only paths matching these patterns (gitignore-style globs):
{scope_paths}

Checks to run before you finish, fixing and rerunning any that fail within scope:
{required_checks}

Diff budget: at most {diff_budget_files} files and {diff_budget_lines} added+deleted lines, new files included.
Dependency or lockfile changes allowed only for: {allowed_dependency_changes}
Non-goals:
{non_goals}
Invariants:
{invariants}

Constraints:
- Do not refactor, abstract speculatively, or reformat anything the request does not require.
- Do not commit, push, open or update a PR or draft PR, update an Issue, or write to any external service.
- Do not spawn subagents and do not call other providers.
- Proceed on in-scope decisions with reasonable assumptions, and report every assumption you made.
- When a check fails, fix it within scope and rerun it.

Stop and return status "stopped" (with trigger, findings, options, recommendation) instead of continuing when:
- out_of_scope_path: the work needs a change outside the scope patterns
- dependency_change: the work needs a dependency or lockfile change that is not allowed above
- public_api_change: the work needs a public API change that the acceptance criteria do not ask for
- diff_budget_exceeded: the work cannot fit in the diff budget

Your final message must be the JSON object required by the output schema.
```
