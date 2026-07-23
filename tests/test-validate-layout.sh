#!/usr/bin/env bash
# test-validate-layout.sh — scripts/validate-layout.sh のstandaloneテスト
# 実$HOME・実repoには一切触れず、mktemp -d に mini repo fixture(実git repo)を構築して検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SCRIPT="$REPO_ROOT/scripts/validate-layout.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0

assert_exit_zero() {
  local desc="$1" rc="$2"
  if [[ "$rc" -eq 0 ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (exit=$rc)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_exit_nonzero() {
  local desc="$1" rc="$2"
  if [[ "$rc" -ne 0 ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected non-zero exit, got 0)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected output to contain: $needle)" >&2
    echo "--- actual output ---" >&2
    echo "$haystack" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
  echo "FAIL: validate-layout script not found or not executable: $VALIDATE_SCRIPT" >&2
  exit 1
fi

# fixture repo: manifest整合が取れた最小構成(claude/codex/shared)を実git repoとして構築する。
# shared/rules/rule-a.md は claude/CLAUDE.md の @~/.agents/rules/ import で、
# shared/rules/rule-b.md は sync-shared-rules.sh の SYNC_MAP で、それぞれ別経路で消費させる。
build_fixture() {
  local repo="$1"
  mkdir -p "$repo/install" "$repo/scripts" \
    "$repo/claude/rules" "$repo/claude/agents" "$repo/claude/githooks" \
    "$repo/codex" \
    "$repo/shared/bin" "$repo/shared/rules"

  cp "$VALIDATE_SCRIPT" "$repo/scripts/validate-layout.sh"
  chmod +x "$repo/scripts/validate-layout.sh"
  mkdir -p "$repo/scripts/lib"
  cp "$REPO_ROOT/scripts/lib/scan-model-pins.py" "$repo/scripts/lib/scan-model-pins.py"

  cat > "$repo/install/manifest.tsv" <<'EOF'
# fixture manifest
link-file	claude/CLAUDE.md	.claude/CLAUDE.md
link-dir	claude/rules	.claude/rules
link-dir	claude/agents	.claude/agents
link-file	codex/AGENTS.md	.codex/AGENTS.md
link-dir	shared/rules	.agents/rules
link-dir	shared/bin	.agents/bin
EOF

  printf '# CLAUDE.md (fixture)\n@~/.agents/rules/rule-a.md\n' > "$repo/claude/CLAUDE.md"
  echo "# gitignore (fixture)" > "$repo/claude/.gitignore"
  echo "# README (fixture)" > "$repo/claude/README.md"
  echo "# pre-commit hook (fixture)" > "$repo/claude/githooks/pre-commit"
  echo "# sample rule (fixture)" > "$repo/claude/rules/sample.md"
  echo "# sample agent (fixture)" > "$repo/claude/agents/sample.md"
  echo "# AGENTS.md (fixture)" > "$repo/codex/AGENTS.md"

  printf '#!/usr/bin/env bash\nSYNC_MAP=$(cat <<'"'"'EOF'"'"'\nrule-b\tcodex/AGENTS.md\nEOF\n)\n' > "$repo/shared/bin/sync-shared-rules.sh"
  chmod +x "$repo/shared/bin/sync-shared-rules.sh"
  echo "# rule-a (consumed via CLAUDE.md import)" > "$repo/shared/rules/rule-a.md"
  echo "# rule-b (consumed via SYNC_MAP)" > "$repo/shared/rules/rule-b.md"

  git -C "$repo" init -q
  git -C "$repo" add -A
}

run_validate() {
  local repo="$1"
  "$repo/scripts/validate-layout.sh"
}

# =========================================================================
# 1. 正常構成は PASS する
# =========================================================================
REPO1="$SANDBOX/repo1"
build_fixture "$REPO1"
mkdir -p "$REPO1/claude/agents/.pytest_cache" "$REPO1/tests"
echo "allowed local cache" > "$REPO1/claude/agents/.pytest_cache/CACHEDIR.TAG"
echo 'fixture path: /home/exampleuser' > "$REPO1/tests/absolute-home-fixture.txt"
git -C "$REPO1" add tests/absolute-home-fixture.txt
out=""
rc=0
out="$(run_validate "$REPO1" 2>&1)" || rc=$?
assert_exit_zero "正常構成は exit 0" "$rc"
assert_contains "正常構成は PASS メッセージを出す" "$out" "PASS: no layout violations found"

# =========================================================================
# 2. 禁止runtime名の追跡は非ゼロ+対象列挙
# =========================================================================
REPO2="$SANDBOX/repo2"
build_fixture "$REPO2"
echo '{"fixture":"forbidden"}' > "$REPO2/shared/bin/history.jsonl"
git -C "$REPO2" add -A
out=""
rc=0
out="$(run_validate "$REPO2" 2>&1)" || rc=$?
assert_exit_nonzero "禁止runtime名の追跡は失敗する" "$rc"
assert_contains "禁止runtime名が列挙される" "$out" "forbidden runtime name tracked: shared/bin/history.jsonl"

# =========================================================================
# 3. 絶対home pathの追跡は非ゼロ+対象列挙
# =========================================================================
REPO3="$SANDBOX/repo3"
build_fixture "$REPO3"
echo "see /home/exampleuser/notes for details" > "$REPO3/claude/agents/leaky.md"
git -C "$REPO3" add -A
out=""
rc=0
out="$(run_validate "$REPO3" 2>&1)" || rc=$?
assert_exit_nonzero "絶対home pathの追跡は失敗する" "$rc"
assert_contains "絶対home pathが列挙される" "$out" "absolute home path in claude/agents/leaky.md:1: /home/exampleuser"

# =========================================================================
# 4. manifestが4列(余剰列)だと非ゼロ+対象列挙
# =========================================================================
REPO4="$SANDBOX/repo4"
build_fixture "$REPO4"
printf 'link-file\tclaude/rules/sample.md\t.claude/rules/sample.md\textra-column\n' >> "$REPO4/install/manifest.tsv"
git -C "$REPO4" add -A
out=""
rc=0
out="$(run_validate "$REPO4" 2>&1)" || rc=$?
assert_exit_nonzero "manifestの4列行は失敗する" "$rc"
assert_contains "4列違反のエラーメッセージ" "$out" "3列が必要です(実際: 4列)"

# =========================================================================
# 5. manifest外(かつallowlist外)のtracked fileは非ゼロ+対象列挙
# =========================================================================
REPO5="$SANDBOX/repo5"
build_fixture "$REPO5"
echo "# untracked-by-manifest fixture file" > "$REPO5/claude/orphan.md"
git -C "$REPO5" add -A
out=""
rc=0
out="$(run_validate "$REPO5" 2>&1)" || rc=$?
assert_exit_nonzero "manifest外tracked fileは失敗する" "$rc"
assert_contains "manifest外tracked fileが列挙される" "$out" "tracked file not covered by manifest or allowlist: claude/orphan.md"

# =========================================================================
# 6. 未消費shared ruleは非ゼロ+対象列挙
# =========================================================================
REPO6="$SANDBOX/repo6"
build_fixture "$REPO6"
echo "# orphan rule (consumed by nothing)" > "$REPO6/shared/rules/rule-orphan.md"
git -C "$REPO6" add -A
out=""
rc=0
out="$(run_validate "$REPO6" 2>&1)" || rc=$?
assert_exit_nonzero "未消費shared ruleは失敗する" "$rc"
assert_contains "未消費shared ruleが列挙される" "$out" "shared rule not consumed by SYNC_MAP or claude/CLAUDE.md import: shared/rules/rule-orphan.md"

# =========================================================================
# 7. 危険設定はwaiverなしで非ゼロ、有効waiverがあればWARNのみでPASS
# =========================================================================
REPO7="$SANDBOX/repo7"
build_fixture "$REPO7"
echo '{"permissions": {"defaultMode": "bypassPermissions", "disableBypassPermissionsMode": "disable"}}' > "$REPO7/claude/settings.json"
printf 'link-file\tclaude/settings.json\t.claude/settings.json\n' >> "$REPO7/install/manifest.tsv"
git -C "$REPO7" add -A
out=""
rc=0
out="$(run_validate "$REPO7" 2>&1)" || rc=$?
assert_exit_nonzero "危険設定はwaiverなしで失敗する" "$rc"
assert_contains "危険設定が違反として列挙される" "$out" "dangerous setting without waiver: claude/settings.json:1: bypassPermissions"

# 有効期限内のwaiver行を追加するとWARNのみでPASSする(environmentはallowlist登録が必要)
mkdir -p "$REPO7/docs/waivers"
printf 'fixture-env\n' > "$REPO7/docs/waivers/environments.txt"
FUTURE_DATE="$(date -d '+30 days' +%F 2>/dev/null || date -v+30d +%F)"
printf 'claude/settings.json\tbypassPermissions\tfixture-env\t%s\ttest waiver\n' "$FUTURE_DATE" > "$REPO7/docs/waivers/settings-waivers.tsv"
git -C "$REPO7" add -A
out=""
rc=0
out="$(run_validate "$REPO7" 2>&1)" || rc=$?
assert_exit_zero "有効waiverがあればPASSする" "$rc"
assert_contains "waiver済み危険設定はWARNとして出力される" "$out" "(waived: see docs/waivers/settings-waivers.tsv)"

# 期限切れwaiverは失敗する
printf 'claude/settings.json\tbypassPermissions\tfixture-env\t2020-01-01\texpired waiver\n' > "$REPO7/docs/waivers/settings-waivers.tsv"
git -C "$REPO7" add -A
out=""
rc=0
out="$(run_validate "$REPO7" 2>&1)" || rc=$?
assert_exit_nonzero "期限切れwaiverは失敗する" "$rc"

# waiver schema違反はそれ自体が失敗する(H-008): 列数不足・空reason・不正日付・未承認environment
for bad in \
  'claude/settings.json\tbypassPermissions\tfixture-env\t2099-01-01' \
  'claude/settings.json\tbypassPermissions\tfixture-env\t2099-01-01\t' \
  'claude/settings.json\tbypassPermissions\tfixture-env\t2099-13-45\treason' \
  'claude/settings.json\tbypassPermissions\tunknown-env\t2099-01-01\treason'; do
  printf "%b\n" "$bad" > "$REPO7/docs/waivers/settings-waivers.tsv"
  git -C "$REPO7" add -A
  out=""
  rc=0
  out="$(run_validate "$REPO7" 2>&1)" || rc=$?
  assert_exit_nonzero "waiver schema違反行($bad)は失敗する" "$rc"
done

# =========================================================================
# 8. generic agent内のproject固有sectionは非ゼロ+対象列挙
# =========================================================================
REPO8="$SANDBOX/repo8"
build_fixture "$REPO8"
printf '\n## Primary Focus（プロジェクト固有）\n' >> "$REPO8/claude/agents/sample.md"
git -C "$REPO8" add -A
out=""
rc=0
out="$(run_validate "$REPO8" 2>&1)" || rc=$?
assert_exit_nonzero "generic agentのproject固有sectionは失敗する" "$rc"
assert_contains "project固有sectionのfileが列挙される" "$out" "project-specific section in generic agent"

# =========================================================================
# 9. link-dir配下の未知local artifactは非ゼロ、許可cacheは正常系でPASS済み
# =========================================================================
REPO9="$SANDBOX/repo9"
build_fixture "$REPO9"
echo "unknown" > "$REPO9/claude/agents/.unknown-runtime"
out=""
rc=0
out="$(run_validate "$REPO9" 2>&1)" || rc=$?
assert_exit_nonzero "link-dir配下の未知artifactは失敗する" "$rc"
assert_contains "未知artifactが列挙される" "$out" "unapproved local artifact under source tree: claude/agents/.unknown-runtime"

# =========================================================================
# 10. manifest source symlinkがrepo外を指す場合は非ゼロ
# =========================================================================
REPO10="$SANDBOX/repo10"
build_fixture "$REPO10"
echo "outside" > "$SANDBOX/outside.md"
ln -s "$SANDBOX/outside.md" "$REPO10/claude/agents/outside.md"
git -C "$REPO10" add claude/agents/outside.md
out=""
rc=0
out="$(run_validate "$REPO10" 2>&1)" || rc=$?
assert_exit_nonzero "repo外を指すmanifest source symlinkは失敗する" "$rc"
assert_contains "repo外sourceの実体pathが列挙される" "$out" "tracked symlink points outside repo"

# =========================================================================
# 11. skill frontmatter schema違反は非ゼロ(name不一致・comma allowed-tools)
# =========================================================================
REPO11="$SANDBOX/repo11"
build_fixture "$REPO11"
mkdir -p "$REPO11/claude/skills/good-skill" "$REPO11/claude/skills/bad-skill"
printf -- '---\nname: good-skill\ndescription: A valid fixture skill for schema checks.\nallowed-tools: Bash Read\n---\n# ok\n' > "$REPO11/claude/skills/good-skill/SKILL.md"
printf -- '---\nname: Wrong:Name\ndescription: Bad fixture.\nallowed-tools: Bash, Read\n---\n# bad\n' > "$REPO11/claude/skills/bad-skill/SKILL.md"
printf 'link-dir\tclaude/skills/good-skill\t.claude/skills/good-skill\nlink-dir\tclaude/skills/bad-skill\t.claude/skills/bad-skill\n' >> "$REPO11/install/manifest.tsv"
git -C "$REPO11" add -A
out=""
rc=0
out="$(run_validate "$REPO11" 2>&1)" || rc=$?
assert_exit_nonzero "skill schema違反は失敗する" "$rc"
assert_contains "name不一致が列挙される" "$out" "name 'Wrong:Name' != directory 'bad-skill'"
assert_contains "comma区切りallowed-toolsが列挙される" "$out" "allowed-tools must be space-separated"

# =========================================================================
# 11b. agent frontmatter / TOML の full model pin はwaiverなしで非ゼロ(H-001)
# =========================================================================
REPO11B="$SANDBOX/repo11b"
build_fixture "$REPO11B"
printf -- '---\nname: sample\nmodel: claude-foo-1\n---\n' > "$REPO11B/claude/agents/sample.md"
printf -- '---\nname: quoted\nmodel: "claude-foo-2"\n---\n' > "$REPO11B/claude/agents/quoted.md"
mkdir -p "$REPO11B/codex"
printf 'model = "claude-foo-1"\n' > "$REPO11B/codex/example.toml"
printf "model = 'claude-foo-3'\n" > "$REPO11B/codex/literal.toml"
git -C "$REPO11B" add -A
out=""
rc=0
out="$(run_validate "$REPO11B" 2>&1)" || rc=$?
assert_exit_nonzero "agent frontmatterのfull model pinは失敗する" "$rc"
assert_contains "plain YAML pinが列挙される" "$out" "claude/agents/sample.md:3: full model pin 'claude-foo-1'"
assert_contains "quoted YAML pinが列挙される" "$out" "claude/agents/quoted.md:3: full model pin 'claude-foo-2'"
assert_contains "TOML basic string pinが列挙される" "$out" "codex/example.toml:1: full model pin 'claude-foo-1'"
assert_contains "TOML literal string pinが列挙される" "$out" "codex/literal.toml:1: full model pin 'claude-foo-3'"

# =========================================================================
# 11c. broad permission allow(bare tool / 広域Bash wildcard)は非ゼロ(H-007)
# =========================================================================
REPO11C="$SANDBOX/repo11c"
build_fixture "$REPO11C"
printf '{"permissions": {"disableBypassPermissionsMode": "disable", "allow": ["Read", "Bash(git *)", "Bash(npm *)", "Bash(uv run *)", "Bash(npm run test*)", "Write(**)"]}}\n' > "$REPO11C/claude/settings.json"
printf 'link-file\tclaude/settings.json\t.claude/settings.json\n' >> "$REPO11C/install/manifest.tsv"
git -C "$REPO11C" add -A
out=""
rc=0
out="$(run_validate "$REPO11C" 2>&1)" || rc=$?
assert_exit_nonzero "broad permission allowは失敗する" "$rc"
assert_contains "bare Read allowが列挙される" "$out" "broad permission allow 'Read'"
assert_contains "広域Bash wildcardが列挙される" "$out" "broad permission allow 'Bash(git *)'"
assert_contains "runner wildcard(npm)が列挙される" "$out" "broad permission allow 'Bash(npm *)'"
assert_contains "runner wildcard(uv run)が列挙される" "$out" "broad permission allow 'Bash(uv run *)'"
assert_contains "unsupported path rule(Write)が列挙される" "$out" "unsupported path-scoped permission rule (matches nothing in current Claude Code): 'Write(**)'"
assert_contains "no-space runner wildcardが列挙される" "$out" "no-space runner wildcard in allow: 'Bash(npm run test*)'"

# =========================================================================
# 11e. bypass lockout の欠落・誤配置・誤値は非ゼロ(H-012)
# =========================================================================
REPO11E="$SANDBOX/repo11e"
build_fixture "$REPO11E"
printf '{"permissions": {"defaultMode": "default"}, "disableBypassPermissionsMode": "disable"}\n' > "$REPO11E/claude/settings.json"
printf 'link-file\tclaude/settings.json\t.claude/settings.json\n' >> "$REPO11E/install/manifest.tsv"
git -C "$REPO11E" add -A
out=""
rc=0
out="$(run_validate "$REPO11E" 2>&1)" || rc=$?
assert_exit_nonzero "root 配置の lockout は失敗する" "$rc"
assert_contains "lockout 欠落(permissions 配下)が列挙される" "$out" "bypass lockout contract"
assert_contains "root 誤配置キーが列挙される" "$out" "misplaced root-level settings key: 'disableBypassPermissionsMode'"

printf '{"permissions": {"defaultMode": "default", "disableBypassPermissionsMode": "enable"}}\n' > "$REPO11E/claude/settings.json"
git -C "$REPO11E" add -A
out=""
rc=0
out="$(run_validate "$REPO11E" 2>&1)" || rc=$?
assert_exit_nonzero "誤値の lockout は失敗する" "$rc"

# =========================================================================
# 11f. .git 全体 deny(sandbox 統合で git workflow を破壊)と
#      sandbox 有効時の presence contract 欠落は非ゼロ(H-018/H-014)
# =========================================================================
REPO11F="$SANDBOX/repo11f"
build_fixture "$REPO11F"
printf '{"permissions": {"defaultMode": "default", "disableBypassPermissionsMode": "disable", "deny": ["Edit(.git/**)"]}, "sandbox": {"enabled": true}}\n' > "$REPO11F/claude/settings.json"
printf 'link-file\tclaude/settings.json\t.claude/settings.json\n' >> "$REPO11F/install/manifest.tsv"
git -C "$REPO11F" add -A
out=""
rc=0
out="$(run_validate "$REPO11F" 2>&1)" || rc=$?
assert_exit_nonzero ".git 全体 deny は失敗する" "$rc"
assert_contains "git-workflow-breaking deny が列挙される" "$out" "git-workflow-breaking deny: 'Edit(.git/**)'"
assert_contains "狭域 .git 保護の欠落が列挙される" "$out" "missing required deny rule for sandboxed settings: 'Edit(.git/config)'"
assert_contains ".env OS 境界の欠落が列挙される" "$out" "missing required deny rule for sandboxed settings: 'Read(//**/.env)'"

# =========================================================================
# 11g. WebFetch(domain:) allow / sandbox.network.allowedDomains による
#      effective pre-allow と、素の uv allow は非ゼロ(H-007/H-019)
# =========================================================================
REPO11G="$SANDBOX/repo11g"
build_fixture "$REPO11G"
printf '{"permissions": {"defaultMode": "default", "disableBypassPermissionsMode": "disable", "allow": ["WebFetch(domain:github.com)", "Bash(uv run pytest *)"]}, "sandbox": {"network": {"allowedDomains": ["example.com"]}}}\n' > "$REPO11G/claude/settings.json"
printf 'link-file\tclaude/settings.json\t.claude/settings.json\n' >> "$REPO11G/install/manifest.tsv"
git -C "$REPO11G" add -A
out=""
rc=0
out="$(run_validate "$REPO11G" 2>&1)" || rc=$?
assert_exit_nonzero "effective pre-allowed domain は失敗する" "$rc"
assert_contains "WebFetch 由来の domain が列挙される" "$out" "pre-allowed egress domain: 'github.com'"
assert_contains "allowedDomains 由来の domain が列挙される" "$out" "pre-allowed egress domain: 'example.com'"
assert_contains "素の uv allow が列挙される" "$out" "sandbox-incompatible uv allow: 'Bash(uv run pytest *)'"

# =========================================================================
# 11d. model scanner は非対応YAML構文で fail-closed になる(H-001)
# =========================================================================
REPO11D="$SANDBOX/repo11d"
build_fixture "$REPO11D"
printf -- '---\nname: quoted-key\n"model": "claude-x-1"\n---\n' > "$REPO11D/claude/agents/sample.md"
git -C "$REPO11D" add -A
out=""
rc=0
out="$(run_validate "$REPO11D" 2>&1)" || rc=$?
assert_exit_nonzero "非対応YAML構文(quoted key)でvalidatorが失敗する" "$rc"
assert_contains "scanner失敗が明示される" "$out" "model pin scan failed"

# =========================================================================
# 12. active treeのstale reference(旧slash command等)は非ゼロ
# =========================================================================
REPO12="$SANDBOX/repo12"
build_fixture "$REPO12"
printf '# stale fixture\nrun /gh:start 42 to begin\n' >> "$REPO12/claude/rules/sample.md"
git -C "$REPO12" add -A
out=""
rc=0
out="$(run_validate "$REPO12" 2>&1)" || rc=$?
assert_exit_nonzero "stale reference(旧slash command)は失敗する" "$rc"
assert_contains "stale referenceが列挙される" "$out" "stale reference in claude/rules/sample.md"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
