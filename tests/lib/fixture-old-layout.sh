#!/usr/bin/env bash
# fixture-old-layout.sh — 旧whole-directory symlink構成を再現するfixture library
# migrationテストからsourceして build_old_layout <sandbox_dir> を呼び出す。
# 実$HOMEには一切触れない。

# sandbox_dir配下に疑似repository(agents-toolkit/{claude,codex,shared})と
# $sandbox_dir/home/.claude, .codex, .agents のwhole-directory symlinkを構築する
build_old_layout() {
  local sandbox_dir="$1"
  local repo="$sandbox_dir/agents-toolkit"

  mkdir -p "$repo/claude/rules" "$repo/claude/skills/sample-skill" "$repo/codex/skills/sample-skill" "$repo/shared/rules"
  git -C "$repo" init -q

  # tracked source (git addしてcommitする)
  echo "# CLAUDE.md (fixture)" > "$repo/claude/CLAUDE.md"
  echo "# sample rule (fixture)" > "$repo/claude/rules/sample.md"
  echo "# claude sample skill (fixture)" > "$repo/claude/skills/sample-skill/SKILL.md"
  echo "# AGENTS.md (fixture)" > "$repo/codex/AGENTS.md"
  echo "# sample skill (fixture)" > "$repo/codex/skills/sample-skill/SKILL.md"
  echo "# shared rule (fixture)" > "$repo/shared/rules/sample.md"
  git -C "$repo" add claude codex shared
  git -C "$repo" \
    -c user.email="fixture@example.com" \
    -c user.name="fixture" \
    commit -q -m "fixture: initial tracked source"

  # untracked疑似runtime (credentials, sessions, cache, DB等)
  echo "FAKE" > "$repo/claude/.credentials.json"
  mkdir -p "$repo/claude/projects/p1"
  echo '{"fake":"session"}' > "$repo/claude/projects/p1/x.jsonl"

  echo "FAKE" > "$repo/codex/auth.json"
  : > "$repo/codex/state.sqlite"

  mkdir -p "$repo/shared/skills/agmsg/db"
  : > "$repo/shared/skills/agmsg/db/messages.db"

  # private overlay (machine固有設定、実directoryへ移動する対象)
  echo "FAKE local override" > "$repo/claude/CLAUDE.local.md"
  echo "FAKE config" > "$repo/codex/config.toml"

  # 旧nested config候補(source tree外のmigration archiveへ退避する対象)
  mkdir -p "$repo/claude/.agents"
  echo "FAKE legacy nested config" > "$repo/claude/.agents/legacy.md"

  # skill state exception(claude/skills/config-audit/audit-history.jsonl は
  # link-dir source(claude/skills)配下だがXDG stateへ移動する例外対象)
  mkdir -p "$repo/claude/skills/config-audit"
  echo '{"fake":"audit"}' > "$repo/claude/skills/config-audit/audit-history.jsonl"

  # link-dir source配下で許可するlocal開発artifact
  mkdir -p "$repo/codex/skills/sample-skill/.pytest_cache"
  echo "FAKE pytest cache" > "$repo/codex/skills/sample-skill/.pytest_cache/CACHEDIR.TAG"

  # __pycache__ (delete candidateだが移動せず残置・警告のみ)
  mkdir -p "$repo/codex/skills/sample-skill/__pycache__"
  : > "$repo/codex/skills/sample-skill/__pycache__/x.pyc"

  # 旧whole-directory symlink構成の再現
  mkdir -p "$sandbox_dir/home"
  ln -s "$repo/claude" "$sandbox_dir/home/.claude"
  ln -s "$repo/codex" "$sandbox_dir/home/.codex"
  ln -s "$repo/shared" "$sandbox_dir/home/.agents"
}
