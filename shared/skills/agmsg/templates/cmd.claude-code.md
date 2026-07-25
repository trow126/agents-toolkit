---
name: agmsg
description: Cross-agent messaging through the bundled SQLite scripts. Use to inspect identity/inbox/team/history or explicitly send, join, switch roles, change delivery, spawn, or despawn agents. Never access the DB or team files directly.
---

# /agmsg for Claude Code

Read `~/.agents/skills/agmsg/references/command-catalog.md`. Use only scripts under `~/.agents/skills/agmsg/scripts/`; there is no `register.sh`.

## Identity

Run `whoami.sh "$(pwd)" claude-code` unless identity is already known in this session.

- One identity: retain `AGENT` and `TEAMS`.
- Multiple identities: ask which name to use.
- Not joined: show available teams, ask for team and agent name, then use `join.sh`.
- Suggested reusable identities: show them and ask whether to reuse or create a name.

After joining, explicitly ask for delivery mode. Claude Code supports `monitor`, `turn`, `both`, and `off`; recommend `monitor` but wait for the user's choice. Follow the `AGMSG-DIRECTIVE` printed by `delivery.sh`.

## Commands and authority

- No argument, `history`, `team`, `status`: read-only scripts.
- `send`, `actas`, `drop`, `mode`, `reset`, `join`: modify local agmsg state only when explicitly requested.
- `spawn` and `despawn`: launch or terminate the explicitly named member. `--force` is destructive and must be explicitly present.

For every `send.sh` call, the message argument must be shell single-quoted. Escape an embedded single quote with the standard `'\''` sequence; never use double quotes because `$name` and command substitutions may expand and silently alter the message.

Before changing an `actas` role, claim its exclusivity lock. Stop only an existing matching Monitor task; never guess a task ID. After role changes, follow the reference workflow to restart the correct subscription.

Report script output and fail on ambiguous team/identity, held actas lock, unsupported mode, timeout, or missing registration. Do not edit SQLite, config, team, lock, or placement files directly.
