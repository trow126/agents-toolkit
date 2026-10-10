# Shared research

Done once per run in the main session, before the Workflow, because every skill needs the same picture of what changed. The digest goes to every per-skill generator, so keep it to facts with sources.

1. Read `<run_dir>/run.json` for `since` (the date of the previous finished run, or none).
2. Start three fresh agents in one message (Agent tool, `general-purpose`), each read-only and told the date and `since`:
   - **Official**: current Claude Code skill, subagent, Workflow, and hook guidance (code.claude.com docs and changelog, the installed version), prompting guidance for the current Claude models, Codex CLI skill and `codex exec` changes, and the Agent Skills specification. Only changes after `since` when it is set.
   - **Research**: peer-reviewed or arXiv work after `since` (or the last 12 months) on agent instructions, skill design, evaluation of skills, and anything the skills' own `evidence` files cite that has been superseded.
   - **Local sources**: the directories in `LOCAL_SOURCES` of `${XDG_CONFIG_HOME:-~/.config}/agents-toolkit/skill-tuneup.env` (colon-separated). Skip this agent when the file or the key is absent, and say so in the digest; it is optional.
3. Each agent returns findings with source URL or path, date, whether it opened the source, and which kinds of skill the finding affects.
4. Write `<run_dir>/research.md`: a `## Findings` list (one line per fact, source and date at the end, `[unverified]` when the agent only saw a snippet) and a `## Coverage` paragraph (what was searched, what was skipped). Verify the few findings that would change many skills yourself before writing them as fact.
