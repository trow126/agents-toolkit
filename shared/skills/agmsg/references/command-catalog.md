# agmsg command catalog

Set `S=~/.agents/skills/agmsg/scripts` and always pass the canonical current project path expected by the scripts.

## Identity and onboarding

- Identify: `$S/whoami.sh "$(pwd)" <codex|claude-code>`.
- Join: `$S/join.sh <team> <agent> <type> "$(pwd)"`.
- After joining, set delivery with `$S/delivery.sh set <mode> <type> "$(pwd)"` and then check the inbox.
- Never invent a team or agent when `whoami` returns multiple candidates; ask the user.

Claude Code onboarding choices are `monitor` (recommended), `turn`, `both`, and `off`. Codex choices are `turn` (default), `off`, and beta `monitor`; reject `both`.

## Read operations

- Inbox: `$S/inbox.sh <team> <agent>` for each registered team.
- History: `$S/history.sh <team> <agent>`.
- Team: `$S/team.sh <team>`.
- Delivery: `$S/delivery.sh status <type> "$(pwd)"`.
- Identities: `$S/identities.sh "$(pwd)" <type>`.

Use the exact argument shape printed by script `--help` when it differs from the summary above.

## Send

Resolve exactly one target team, then run:

```bash
$S/send.sh <team> <from-agent> <to-agent> '<message>'
```

The message is always single-quoted. Encode an embedded quote as `'\''`. Do not use double quotes, backticks, or command substitution in the message argument.

## Role operations

- `actas <name>`: ensure the name is registered, then use `actas-claim.sh` for Claude Code with the real session ID. `status=held` is a hard stop. Set the session's sender identity only after a successful claim.
- `drop <name>`: use `reset.sh "$(pwd)" <type> <name> [session-id]`; remove only that project registration.
- `reset`: use `reset.sh "$(pwd)" <type>` and report exactly what was removed.

Claude Code role changes must stop only the matching inbox Monitor task if one exists, then start the subscription specified by the delivery directive. If no matching task exists, do not call TaskStop.

## Process operations

- Spawn: `$S/spawn.sh <claude-code|codex> <name> --project "$(pwd)" [documented options]`.
- Despawn: `$S/despawn.sh <team> <from-agent> <name> [--timeout <seconds>]`.
- Forced despawn: add `--force` only when explicitly requested or after reporting a graceful timeout and receiving approval.

Spawn waits for readiness by default where supported. A timeout or nonzero status is reported, not converted to success. Despawn affects only a member previously placed by spawn; never kill an unrelated pane or process.

## Delivery

Use `delivery.sh set` and follow its printed directive. Claude Code monitor uses its Monitor task and XDG state. Codex monitor may install/use an optional shim, requires `~/.agents/bin` on PATH, and begins on the first turn of a newly restarted session. Do not modify shell profiles automatically.

## Safety

All DB, WAL, pid, lock, team, and placement state belongs under the script-resolved XDG location. Never read or edit those files directly. Script errors, conflicting identities, stale locks, unsupported modes, and missing dependencies are explicit failures.
