# cross-critic workflow

`~/.claude/bin/cross-critic` runs the critics and checks your synthesis. Nothing it does writes to the repository; the run directory is `${XDG_STATE_HOME:-~/.local/state}/agents-toolkit/cross-critic/<run-id>/`.

## Run

1. The document must be a UTF-8 file of at most 64 KiB. If it exists only in the conversation, write it to your scratchpad first. It goes to another provider, so leave out secrets, credentials, and private data; `run` refuses text that looks like a token or key.
2. From the main session, with `Bash(run_in_background=true)`:

   ```bash
   ~/.claude/bin/cross-critic run <document> --author <your exact model id> [--gate] [--repo <dir>]
   ```

   - `--author` is the model of this main session (the document's author). With `--gate`, the Claude critic is the route's gate model unless the author is that model, in which case the route's alternate model is used. A document is never criticized by the model that wrote it.
   - The critics may read files under the repository (`--repo`, default: the repository of the current directory, or the document's directory) to check the document's claims. Both are read-only: the Codex critic runs `codex exec -s read-only`; the Claude critic runs `claude -p --tools Read,Grep,Glob`. The managed policy ignores `--allowedTools`, so `--tools` is what restricts the Claude critic. The children run with `AGENTS_TOOLKIT_SLACK_NOTIFY=off`, through `bash -lc` so that `codex` and `claude` are on `PATH`.
   - `--dry-run` prints both commands without calling a model.
3. On the completion notification, read the printed summary. `run` exits non-zero when a critic failed, returned output that does not match the schema or the document hash, or when `git status` of the repository changed. Report that failure; do not continue silently with one critic.
4. `run` writes `<run>/findings.json` (each finding with an ID: `X<n>` from the Codex critic, `C<n>` from the Claude critic) and `<run>/synthesis.template.md` with one table row per finding.

## Synthesis

Copy the template to `<run>/synthesis.md` and complete it. The table must keep exactly these columns:

| ID | 指摘 | 出所 | 優先度 | 判定 | 理由 |
|---|---|---|---|---|---|
| X1, C2 | 統合した指摘 | 両方 | 高 | 採用 | 何をどう直すか |

- Merge duplicates: one row may list several IDs. Every ID in `findings.json` must appear in some row.
- `出所`: the critic label printed by `run` when all IDs of the row come from one critic, or `両方` when the row merges findings of both critics.
- `優先度`: `高`, `中`, or `低`. Start from the critic's severity (high → 高, medium → 中, low → 低). A `両方` row is one level above the highest severity of its IDs (already `高` stays `高`): agreement of two providers is the signal this skill exists for.
- `判定`: `採用` or `不採用`, for every row. `理由` is never empty: for `採用`, the change you will make; for `不採用`, why the finding does not hold or does not matter here, with evidence. "全件不採用" is allowed only with a specific reason per row.
- Below the table, add `## Notes` with anything the critics could not check and any change of route.

Then run `~/.claude/bin/cross-critic finish <run>`. It checks the table against `findings.json` and the rules above, checks `git status` again, and writes `<run>/result.md` with your synthesis and both raw outputs. Fix the synthesis, never the check.

## Critic prompt

`run` fills this template and sends the same text to every critic.

```text
You are an independent critic of the document below. Another critic from a different model provider may review the same document separately; you will not see its output.

Your job is to criticize, not to judge. Do not approve or reject the document, do not say whether it is correct overall, and do not score it. Returning few findings is not approval.

Look for:
- objection: a claim, assumption, or decision you would argue against, and why.
- oversight: something the document should address but does not (a risk, case, dependency, failure mode, confound, leak, or missing check).
- alternative_explanation: another explanation for an observation or expected result that the document attributes to one cause.
- alternative: a different plan, design, test, or analysis that reaches the same goal, with its trade-off.

Rules:
- Work read-only. You may read files under the working directory to check the document's claims. Do not create, modify, or delete files, do not run commands that change state, and do not contact external services.
- Make each finding concrete: the section or quote it targets, the claim, why it matters, and what evidence or change would resolve it.
- severity is how much the finding could change the decision if it holds (high, medium, low). It is not a verdict on the document.
- Prefer substantive findings over many small ones; return at most 12. Write the finding text in the document's language.
- Answer with only the JSON object required by the output schema. Copy document_sha256 exactly from the line below.

document_sha256: {{DOCUMENT_SHA256}}

<document path="{{DOCUMENT_NAME}}">
{{DOCUMENT}}
</document>
```
