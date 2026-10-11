# gh-issue workflow

## Create

1. Require one existing UTF-8 body file and a valid target repository.
2. Use `issue-writing` to classify the Issue, locate the exact repo/global template, and validate headings, completeness, non-goals, acceptance criteria, and verification.
3. Show the final title/body and create exactly one Issue through the GitHub connector. Do not auto-retry a failed create.
4. Return the confirmed Issue number and URL. Labels, assignees, projects, and follow-up comments require separate requests.

## Close

1. Fetch the Issue, linked PR/state, and stated close criteria.
2. Refuse closure when required evidence is missing or the user targeted the wrong Issue.
3. Close exactly one Issue through the connector. Do not generate or save learnings and do not delete any local or runtime file.

## Retrospective

`retro` separates facts/evidence, interpretation, follow-up proposals, and close conditions. It is in-chat by default. `--apply <path>` requires a normalized path inside the current repository, refuses symlinks escaping the root, and refuses an existing target unless overwrite was explicitly requested.

## Failures

Invalid arguments, unavailable authentication, missing templates, incomplete bodies, repo-external output paths, and failed connector writes are explicit errors. No fallback operation may change external or local state.
