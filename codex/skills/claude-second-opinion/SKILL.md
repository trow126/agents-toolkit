---
name: claude-second-opinion
description: Use when the user explicitly asks for a second opinion from Claude Code, or when Codex itself has low confidence (uncertain trade-off, multi-file impact, ambiguous spec, long-context reading) and an independent opinion from Claude Code Fable would materially reduce risk. Invoke scripts/ask-claude.sh with the user's question on stdin. Do not use for short factual questions, syntax lookups, or tasks where Codex is already confident.
---

# Claude Second Opinion

Use this skill to fetch an independent second opinion from Claude Code Fable when a
question is hard, broad, or ambiguous enough that a different model's view
would reduce risk. The wrapper runs Fable at high effort in safe, non-interactive
`dontAsk` mode, exposes progress on stderr, and handles the API and wall-clock
timeouts needed by long calls.

## Scope

Use this skill for:

- The user says "Claude にも聞いて", "セカンドオピニオン", or similar
- Codex's own confidence is low on a non-trivial design choice
- Reading or summarizing many files at once (Claude's 1M context)
- A second pair of eyes on a code review or architectural trade-off

Do not use this skill for:

- Short factual questions or syntax lookups
- Tasks Codex is already highly confident about
- Anything that should stay private — see the security note below

## Workflow

### 1. Decide whether to invoke

Ask once: would an independent opinion change the answer or your confidence?
If yes, continue. If no, skip the skill.

Do not feed Codex's own draft answer to Claude. Send the original question
unchanged so the two models stay independent (no echo chamber).

### 2. Pick the minimum tool access

Default: pass neither access flag. Claude runs from a private temporary
directory with no tools and sees only the prompt text.

Pass `--include-cwd` only when the question genuinely requires reading files
in the current project and the project contains no secrets. Whenever
`--include-cwd` is on, Claude receives only the read-only `Read`, `Glob`, and
`Grep` tools. Every file Claude reads is sent to the Anthropic API.

Pass `--allow-web` only when current public web information is required. It
enables only `WebSearch` and `WebFetch`; queries, URLs, and fetched content are
part of the Claude exchange. The two flags are additive. `Bash`, `Edit`,
`Write`, `Agent`, and MCP tools are never exposed by this wrapper.

The wrapper uses `dontAsk`, not Plan mode. With no access flags, all tools are
unavailable. With an access flag, only its exact tool list is both exposed and
pre-approved; every other tool remains unavailable.

### 3. Invoke the wrapper

The wrapper lives inside this skill directory. From within a Codex bash tool:

```bash
printf '%s\n' "ここに問い" \
  | bash ~/.codex/skills/claude-second-opinion/scripts/ask-claude.sh \
      --cwd /tmp
```

`--cwd` is required and must resolve to an existing directory other than
`$HOME`. For file-backed questions, run from the project and use
`--cwd "$PWD" --include-cwd`. For prompt-only questions launched from `$HOME`,
use a neutral directory such as `/tmp`. Add `--allow-web` only when step 2
requires it. Add `--timeout <sec>` (default 1200) only when a different positive
wall-clock cap is needed. At the cap, GNU `timeout` sends `TERM`; if the process
does not stop within 10 more seconds, it sends `KILL` and the wrapper exits 137.

The wrapper disables user customizations and session persistence so the opinion stays
independent and cannot recursively invoke Codex through user hooks or plugins. It writes
the prompt and candidate result to mode-protected files in a private temporary directory,
then removes that directory on normal exit and handled signals; a process-wide crash or
`SIGKILL` can still leave temporary data behind. Progress is written to stderr; stdout
contains only Claude's single validated final answer. A timeout, malformed stream, API
error, missing/duplicate result, or empty result fails loudly without retry or model
fallback.

### 4. Present the result

Show Claude's output to the user verbatim under a clearly labelled section
such as `## Claude の意見`. Add Codex's own opinion in a separate section so
the user can compare. Do not silently merge or rewrite Claude's answer.

If Claude disagrees with Codex, briefly note where they differ and which
position Codex now favors and why. The final call is Codex's; do not punt the
decision back to the user without a recommendation.

## Security

`--include-cwd` adds `--add-dir <cwd>` to the `claudecode --model fable`
invocation and exposes only `Read`, `Glob`, and `Grep`, which lets Claude read files in
the project and ship them to Anthropic. Do not use it in
directories containing `.env`, `credentials*`, `secrets*`, private keys, or
production data. When in doubt, omit the flag and quote the relevant snippets
in the prompt instead. Omit `--allow-web` unless public web retrieval is needed.

## Disable

To temporarily disable this skill, either:

- Prefix the `description` field above with `[DISABLED]`, or
- Rename the skill directory: `mv ~/.codex/skills/claude-second-opinion{,.off}`

## Final checklist

Before invoking, verify that:

- The question is hard or broad enough to justify a second opinion.
- The user has not asked for a private/sensitive answer to be quoted only.
- `--include-cwd` is used only in directories without secrets.
- `--allow-web` is used only when current public web information is necessary.
- Codex's own draft answer has not been embedded into the prompt.
- The plan is to show Claude's reply alongside Codex's, not in place of it.
- Enough time remains for the default 20-minute wall-clock cap.
