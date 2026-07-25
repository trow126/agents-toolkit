---
name: agmsg
description: Cross-agent messaging through the bundled SQLite scripts. Use to inspect identity/inbox/team/history or explicitly send, join, switch roles, change delivery, spawn, or despawn agents. Never access the DB or team files directly.
---

# $agmsg for Codex

Read [`references/command-catalog.md`](references/command-catalog.md). Use only scripts under `~/.agents/skills/agmsg/scripts/`; there is no `register.sh`.

## Identity

Run `whoami.sh "$(pwd)" codex` unless identity is already known in this session.

- One identity: retain `AGENT` and `TEAMS`.
- Multiple identities: ask which name to use.
- Not joined: show available teams, ask for team and agent name, then use `join.sh`.
- Suggested reusable identities: show them and ask whether to reuse or create a name.

After joining, explicitly ask for delivery mode. Codex default is `turn`; supported values are `turn`, `off`, and beta `monitor`. `both` is unsupported.

## Commands and authority

- No argument, `history`, `team`, `status`: read-only scripts.
- `send`, `actas`, `drop`, `mode`, `reset`, `join`: modify local agmsg state only when explicitly requested.
- `spawn` and `despawn`: launch or terminate the explicitly named member. `--force` is destructive and must be explicitly present.

For every `send.sh` call, the message argument must be shell single-quoted. Escape an embedded single quote with the standard `'\''` sequence; never use double quotes because `$name` and command substitutions may expand and silently alter the message.

Report script output and fail on ambiguous team/identity, held actas lock, unsupported mode, timeout, or missing registration. Do not edit SQLite, config, team, lock, or placement files directly.

Codex monitor is beta and affects future session startup through the optional shim. Follow the directive printed by `delivery.sh`; never claim the already-running session became monitored without the required restart and first turn.
