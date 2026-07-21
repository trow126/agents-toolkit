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
