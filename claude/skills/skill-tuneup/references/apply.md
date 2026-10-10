# --apply

Implements a finished run. Invoking `/skill-tuneup --apply <run-dir>` is the request to edit the repository files listed below and run the checks; it is not a request to commit, push, or open a PR.

1. Run `~/.claude/bin/skill-tuneup plan <run_dir>`. It fails unless `finish` passed for the run and HEAD is the commit the run inventoried or later with the skill files unchanged; otherwise rerun the default flow for the changed skills. It prints, per skill, the hygiene findings and the candidates whose experiment passed (`PASS`).
2. Load `implementation-quality` and follow its rules for each change. Implement only what `plan` printed. A candidate whose verdict was `KNOWN` is implemented as the known method with its source cited; a `FAIL` or `INCONCLUSIVE` experiment's candidates are not implemented.
3. Keep each skill's change inside its own files plus the contracts the toolkit checks: the skill-pair drift fixture, `docs/contracts/skill-authority.tsv` when a mode changes, inventory rows for new files, and the `metrics:after` block when skill sizes change. Update the skill's own evidence file when a change rests on new evidence.
4. Run the static suite (`tests/test-*.sh` run directly, `scripts/validate-layout.sh`, `scripts/lint-distributed-markdown.sh`, `shared/bin/sync-shared-rules.sh --check`).
5. Report per skill: what changed (files), what was skipped and why, and the check results. Leave the changes uncommitted; the user commits with `git-operations` or `gh-finish`.
