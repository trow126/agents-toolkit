#!/usr/bin/env bash
# validate-layout.sh — repo構造の最終validator(構造更新計画 Phase 6 + 2026-07-23 近代化)
# tracked ファイルと、cutover後のlink-dir配下を対象に、禁止runtime名・絶対home path・manifest整合・
# manifest外のtracked file・未消費shared rule・未許可artifact・危険設定(waiver必須)・
# skill frontmatter schema・stale referenceを検査する。fail-fastせず違反を全件列挙してから非ゼロ終了する。
# 危険設定はdocs/waivers/settings-waivers.tsvの有効なwaiver行がある場合のみWARN扱いとする。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/install/manifest.tsv"
SYNC_SCRIPT="$REPO_ROOT/shared/bin/sync-shared-rules.sh"
CLAUDE_MD="$REPO_ROOT/claude/CLAUDE.md"

cd "$REPO_ROOT"

violations=0
fail() {
  echo "FAIL: $*" >&2
  violations=$((violations + 1))
}
warn() {
  echo "WARN: $*"
}

# =========================================================================
# 1. 禁止runtime名(追跡ファイルに含まれてはならない)
# =========================================================================
echo "== 1. forbidden tracked runtime names =="
FORBIDDEN_BASENAMES=(
  ".credentials.json" "auth.json" "history.jsonl" "session_index.jsonl"
  "installation_id" "messages.db" "settings.local.json" "CLAUDE.local.md" "default.rules"
)
FORBIDDEN_PATHS=("codex/config.toml" "codex/gh.config.toml")

while IFS= read -r f; do
  base="$(basename "$f")"
  for n in "${FORBIDDEN_BASENAMES[@]}"; do
    [[ "$base" == "$n" ]] && fail "forbidden runtime name tracked: $f"
  done
  case "$base" in
    *.sqlite | *.sqlite-*) fail "forbidden runtime name tracked: $f" ;;
  esac
  for p in "${FORBIDDEN_PATHS[@]}"; do
    [[ "$f" == "$p" ]] && fail "forbidden runtime path tracked: $f"
  done
done < <(git ls-files)

# =========================================================================
# 2. 絶対home path(docs/archive/と意図的に絶対pathを使うfixtureは除外)
# =========================================================================
echo "== 2. absolute home paths =="
while IFS= read -r f; do
  case "$f" in
    docs/archive/* | tests/*) continue ;;
  esac
  [[ -f "$f" ]] || continue
  matches="$(grep -InoE '/home/[A-Za-z0-9][A-Za-z0-9_.-]*' "$f" || true)"
  [[ -z "$matches" ]] && continue
  while IFS=: read -r lineno match; do
    fail "absolute home path in $f:$lineno: $match"
  done <<< "$matches"
done < <(git ls-files)

# =========================================================================
# 3. manifest整合(3列固定・source実在+tracked・target重複なし)
# =========================================================================
echo "== 3. manifest integrity =="
declare -a MANIFEST_MODE=()
declare -a MANIFEST_SRC=()
declare -a MANIFEST_TARGET=()
declare -A SEEN_TARGETS=()
line_no=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  field_count=$(awk -F'\t' '{print NF}' <<< "$line")
  if [[ "$field_count" -ne 3 ]]; then
    fail "install/manifest.tsv:$line_no: mode<TAB>source<TAB>target の3列が必要です(実際: ${field_count}列)"
    continue
  fi

  IFS=$'\t' read -r mode src target <<< "$line"

  case "$mode" in
    link-file)
      if [[ ! -f "$REPO_ROOT/$src" ]]; then
        fail "install/manifest.tsv:$line_no: source ファイルが存在しません: $src"
      elif ! git ls-files --error-unmatch -- "$src" > /dev/null 2>&1; then
        fail "install/manifest.tsv:$line_no: source が git 追跡されていません: $src"
      fi
      ;;
    link-dir)
      if [[ ! -d "$REPO_ROOT/$src" ]]; then
        fail "install/manifest.tsv:$line_no: source ディレクトリが存在しません: $src"
      elif [[ -z "$(git ls-files -- "$src")" ]]; then
        fail "install/manifest.tsv:$line_no: source ディレクトリに git 追跡ファイルがありません: $src"
      fi
      ;;
    *)
      fail "install/manifest.tsv:$line_no: 不明な mode '$mode'"
      continue
      ;;
  esac

  if [[ "$mode" == "link-file" && "$target" =~ ^\.agents/skills/[^/]+/SKILL\.md$ ]]; then
    fail "install/manifest.tsv:$line_no: Codex skill は SKILL.md 単体ではなく実ファイルを含むディレクトリを link-dir で配布してください: $target"
  fi

  if [[ -e "$REPO_ROOT/$src" || -L "$REPO_ROOT/$src" ]]; then
    src_real="$(realpath -e -- "$REPO_ROOT/$src")"
    if [[ "$src_real" != "$REPO_ROOT" && "$src_real" != "$REPO_ROOT/"* ]]; then
      fail "install/manifest.tsv:$line_no: source の実体がrepo外を指しています: $src -> $src_real"
    fi
  fi

  if [[ -n "${SEEN_TARGETS[$target]:-}" ]]; then
    fail "install/manifest.tsv:$line_no: target が重複しています: $target (既存: ${SEEN_TARGETS[$target]})"
  fi
  SEEN_TARGETS["$target"]="line $line_no"

  MANIFEST_MODE+=("$mode")
  MANIFEST_SRC+=("$src")
  MANIFEST_TARGET+=("$target")
done < "$MANIFEST"

for ((i = 0; i < ${#MANIFEST_TARGET[@]}; i++)); do
  for ((j = i + 1; j < ${#MANIFEST_TARGET[@]}; j++)); do
    a="${MANIFEST_TARGET[$i]%/}"
    b="${MANIFEST_TARGET[$j]%/}"
    if [[ "$a" == "$b/"* || "$b" == "$a/"* ]]; then
      fail "manifest targets overlap: $a / $b"
    fi
  done
done

while IFS= read -r f; do
  [[ -L "$f" ]] || continue
  if ! link_real="$(realpath -e -- "$f" 2>/dev/null)"; then
    fail "tracked symlink is broken: $f -> $(readlink "$f")"
  elif [[ "$link_real" != "$REPO_ROOT" && "$link_real" != "$REPO_ROOT/"* ]]; then
    fail "tracked symlink points outside repo: $f -> $link_real"
  fi
done < <(git ls-files)

# =========================================================================
# 4. manifest外のtracked file(claude/・codex/・shared/ 配下)
# =========================================================================
echo "== 4. tracked files outside manifest coverage =="
ALLOWLIST_EXACT=("claude/.gitignore" "claude/README.md" "claude/managed-settings.json")
ALLOWLIST_PREFIX=(
  "claude/githooks/"
  "shared/skills/break-consensus/references/"
  "shared/skills/gh-review/references/"
)

is_covered() {
  local f="$1" e p i m s
  for e in "${ALLOWLIST_EXACT[@]}"; do
    [[ "$f" == "$e" ]] && return 0
  done
  for p in "${ALLOWLIST_PREFIX[@]}"; do
    [[ "$f" == "$p"* ]] && return 0
  done
  for ((i = 0; i < ${#MANIFEST_MODE[@]}; i++)); do
    m="${MANIFEST_MODE[$i]}"
    s="${MANIFEST_SRC[$i]}"
    if [[ "$m" == "link-file" && "$f" == "$s" ]]; then
      return 0
    fi
    if [[ "$m" == "link-dir" && "$f" == "$s/"* ]]; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r f; do
  case "$f" in
    claude/* | codex/* | shared/*) ;;
    *) continue ;;
  esac
  # 未commitの削除(index上はtrackedだがworking treeに実体がない)は
  # git ls-files ベースの本checkでは対象外とする(CIのfresh checkoutでは発生しない)
  [[ -f "$f" ]] || continue
  if ! is_covered "$f"; then
    fail "tracked file not covered by manifest or allowlist: $f"
  fi
done < <(git ls-files)

# =========================================================================
# 5. generic agentにprivate project固有sectionを置かない
# =========================================================================
echo "== 5. private project sections in generic agents =="
while IFS= read -r f; do
  if grep -nF 'Primary Focus（プロジェクト固有）' "$f" >/dev/null; then
    fail "project-specific section in generic agent: $f"
  fi
done < <(git ls-files 'claude/agents/*.md')

# =========================================================================
# 6. source tree配下の未許可local artifact
#    旧whole-directory symlink構成ではmigration対象が意図的にrepo内にあるためskipし、
#    cutover後とCIのfresh checkoutで検査する。
# =========================================================================
echo "== 6. local artifacts under source trees =="
old_layout=false
old_layout_count=0
for pair in ".claude:claude" ".codex:codex" ".agents:shared"; do
  home_name="${pair%%:*}"
  repo_name="${pair#*:}"
  if [[ -L "${AGENTS_TOOLKIT_HOME:-$HOME}/$home_name" ]] && \
     [[ "$(readlink -f "${AGENTS_TOOLKIT_HOME:-$HOME}/$home_name")" == "$REPO_ROOT/$repo_name" ]]; then
    old_layout_count=$((old_layout_count + 1))
  fi
done
if [[ "$old_layout_count" -eq 3 ]]; then
  old_layout=true
elif [[ "$old_layout_count" -gt 0 ]]; then
  fail "partial old layout detected: expected 0 or 3 whole-directory symlinks, found $old_layout_count"
fi

if [[ "$old_layout" == "true" ]]; then
  warn "旧whole-directory symlink構成のためlocal artifact検査をskipします。migration後に再実行してください"
else
  declare -A SEEN_LOCAL_ARTIFACTS=()
  while IFS= read -r -d '' f; do
    [[ -n "${SEEN_LOCAL_ARTIFACTS[$f]:-}" ]] && continue
    SEEN_LOCAL_ARTIFACTS["$f"]=1
    case "/$f/" in
      */.venv/* | */.mypy_cache/* | */.pytest_cache/* | */.ruff_cache/* | */__pycache__/*) ;;
      *) fail "unapproved local artifact under source tree: $f" ;;
    esac
  done < <(
    {
      git ls-files --others --exclude-standard -z -- claude codex shared
      git ls-files --others --ignored --exclude-standard -z -- claude codex shared
    }
  )
fi

# =========================================================================
# 7. 未消費shared rule(SYNC_MAP または claude/CLAUDE.md import のどちらにも登場しない)
# =========================================================================
echo "== 7. unconsumed shared rules =="
SYNC_NAMES="$(sed -n "/^SYNC_MAP=\$(cat <<'EOF'\$/,/^EOF\$/p" "$SYNC_SCRIPT" | sed '1d;$d' | awk -F'\t' '{print $1}' | sort -u)"
CLAUDE_MD_NAMES="$(grep -oE '@~/\.agents/rules/[A-Za-z0-9_-]+\.md' "$CLAUDE_MD" | sed -E 's#@~/\.agents/rules/##; s/\.md$//' | sort -u)"

for rule_file in "$REPO_ROOT"/shared/rules/*.md; do
  name="$(basename "$rule_file" .md)"
  if ! grep -qxF "$name" <<< "$SYNC_NAMES" && ! grep -qxF "$name" <<< "$CLAUDE_MD_NAMES"; then
    fail "shared rule not consumed by SYNC_MAP or claude/CLAUDE.md import: shared/rules/$name.md"
  fi
done

# =========================================================================
# 8. Phase 1 inventory completeness / 11-axis audit (H-04)
# =========================================================================
echo "== 8. inventory completeness and audit schema =="
INVENTORY_FILE="$REPO_ROOT/docs/reports/inventory-elements.tsv"
INVENTORY_ERRORS="$(python3 - "$REPO_ROOT" "$INVENTORY_FILE" <<'PYINV'
import csv
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
path = Path(sys.argv[2])
errors = []
expected = [
    "id", "category", "before_path", "after_path", "archive_path", "tags",
    "purpose", "needed", "builtin_alternative", "overlap", "context_load",
    "false_positive", "failure_impact", "verification", "low_cost_model",
    "deterministic_replacement", "disposition", "evidence",
]
axes = [
    "purpose", "needed", "builtin_alternative", "overlap", "context_load",
    "false_positive", "failure_impact", "verification", "low_cost_model",
    "deterministic_replacement", "disposition",
]
if not path.is_file():
    errors.append("docs/reports/inventory-elements.tsv is missing")
else:
    try:
        with path.open(encoding="utf-8", newline="") as fh:
            reader = csv.DictReader(fh, delimiter="\t")
            if reader.fieldnames != expected:
                errors.append(f"inventory header mismatch: {reader.fieldnames!r}")
                rows = []
            else:
                rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        errors.append(f"inventory parse error: {exc}")
        rows = []

    ids = set()
    represented = set()
    for lineno, row in enumerate(rows, 2):
        rid = (row.get("id") or "").strip()
        if not rid:
            errors.append(f"inventory line {lineno}: id is empty")
        elif rid in ids:
            errors.append(f"inventory line {lineno}: duplicate id {rid}")
        ids.add(rid)
        for key in ("category", "before_path", "after_path", "archive_path", "evidence", *axes):
            if not (row.get(key) or "").strip():
                errors.append(f"inventory line {lineno} ({rid or '?'}): {key} is empty")
        for key in ("before_path", "after_path"):
            value = (row.get(key) or "").strip()
            if value and value != "-" and not value.startswith(("~", "$", "active ")) and ";" not in value and " -> " not in value:
                represented.add(value)

    # Every operational script/config surface named by Phase 1 must be an
    # individual row; documentation and generated archives are intentionally
    # outside this coverage set.
    tracked = subprocess.run(
        ["git", "-C", str(root), "ls-files"], check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.splitlines()
    operational = set()
    prefixes = (
        "scripts/", "tests/", "claude/bin/", "claude/hooks/",
        "claude/scripts/", "claude/githooks/", ".github/workflows/", "install/",
    )
    for item in tracked:
        if item == "bootstrap.sh" or item in {
            "claude/settings.json", "claude/managed-settings.json", "codex/hooks.json"
        }:
            operational.add(item)
        elif item.startswith(prefixes):
            # test documentation fixtures are not executable mechanisms.
            if item.startswith("tests/") and not (item.endswith(".sh") or "/lib/" in item):
                continue
            operational.add(item)
    missing = sorted(operational - represented)
    for item in missing:
        errors.append(f"operational element missing from inventory: {item}")

print("\n".join(errors))
PYINV
)"
if [[ -n "$INVENTORY_ERRORS" ]]; then
  while IFS= read -r line; do [[ -n "$line" ]] && fail "inventory audit: $line"; done <<< "$INVENTORY_ERRORS"
fi

# =========================================================================
# 9. security / managed policy / waiver governance
# =========================================================================
echo "== 9. managed owner policy and governed settings =="
WAIVER_FILE="$REPO_ROOT/docs/waivers/settings-waivers.tsv"
WAIVER_ENVS="$REPO_ROOT/docs/waivers/environments.txt"
TODAY="$(date +%F)"
USER_SETTINGS="$REPO_ROOT/claude/settings.json"
MANAGED_SETTINGS="$REPO_ROOT/claude/managed-settings.json"
POLICY_CHECK="$SCRIPT_DIR/check-managed-policy.py"

# waiver file 自体の schema 検査(H-008)。不正行は未使用でも違反。
if [[ -f "$WAIVER_FILE" ]]; then
  wl=0
  while IFS= read -r wrow; do
    wl=$((wl + 1))
    [[ "$wrow" == \#* || -z "$wrow" ]] && continue
    wfields=$(awk -F'\t' '{print NF}' <<< "$wrow")
    if [[ "$wfields" -ne 5 ]]; then
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: 5列必須(実際: ${wfields}列)"
      continue
    fi
    IFS=$'\t' read -r wfile wpattern wenv wexpires wreason <<< "$wrow"
    [[ -z "$wfile" || -z "$wpattern" || -z "$wenv" || -z "$wexpires" || -z "$wreason" ]] && \
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: 空の列がある"
    if [[ ! "$wexpires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || \
       ! date -d "$wexpires" +%F >/dev/null 2>&1 || \
       [[ "$(date -d "$wexpires" +%F)" != "$wexpires" ]]; then
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: expires が実在日の YYYY-MM-DD ではない: '$wexpires'"
    fi
    if [[ -n "$wenv" ]] && { [[ ! -f "$WAIVER_ENVS" ]] || ! grep -qxF "$wenv" <(grep -v '^#' "$WAIVER_ENVS"); }; then
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: 未承認 environment '$wenv'"
    fi
  done < "$WAIVER_FILE"
fi

has_waiver() {
  local file="$1" pname="$2"
  [[ -f "$WAIVER_FILE" ]] || return 1
  while IFS=$'\t' read -r wfile wpattern wenv wexpires wreason; do
    [[ "$wfile" == \#* || -z "$wfile" ]] && continue
    [[ -z "$wpattern" || -z "$wenv" || -z "$wexpires" || -z "$wreason" ]] && continue
    [[ "$wexpires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
    date -d "$wexpires" +%F >/dev/null 2>&1 || continue
    { [[ -f "$WAIVER_ENVS" ]] && grep -qxF "$wenv" <(grep -v '^#' "$WAIVER_ENVS"); } || continue
    if [[ "$wfile" == "$file" && "$wpattern" == "$pname" ]] && ! [[ "$wexpires" < "$TODAY" ]]; then
      return 0
    fi
  done < "$WAIVER_FILE"
  return 1
}

# The owner policy must be in managed scope, and the user file must be free of
# managed keys. The checker enforces bypass/sandbox intent, managed locks,
# helper paths, hooks, and an unambiguous dormant ruleset.
if [[ ! -x "$POLICY_CHECK" ]]; then
  fail "managed policy checker missing or non-executable: scripts/check-managed-policy.py"
else
  POLICY_OUT="$(python3 "$POLICY_CHECK" --user "$USER_SETTINGS" --managed "$MANAGED_SETTINGS" 2>&1)" || \
    fail "managed policy contract: $POLICY_OUT"
fi

# Managed policy is deliberately not linked into ~/.claude; it is installed by
# scripts/install-managed-policy.sh into the documented OS-managed directory.
if grep -q $'\tclaude/managed-settings.json\t' "$MANIFEST" 2>/dev/null; then
  fail "managed settings must not be installed through the user symlink manifest"
fi

# Full model pins use the shared structural scanner. Scanner failures are fatal.
# claude/settings.json の model キー（kind=runtime-pin）は /model コマンドが正式に
# 書き込む runtime 選択のため waiver 不要（可視化のため WARN のみ）。
PIN_SCAN="$(python3 "$SCRIPT_DIR/lib/scan-model-pins.py" "$REPO_ROOT" 2>&1)" || fail "model pin scan failed: $PIN_SCAN"
while IFS=: read -r pfile pline pkind pvalue; do
  if [[ "$pkind" == "runtime-pin" ]]; then
    warn "$pfile:$pline: model=$pvalue (runtime-managed via /model)"
    continue
  fi
  [[ "$pkind" == "pin" ]] || continue
  if has_waiver "$pfile" "full-model-pin"; then
    warn "$pfile:$pline: model=$pvalue (waived)"
  else
    fail "dangerous setting without waiver: $pfile:$pline: full model pin '$pvalue'"
  fi
done <<< "$PIN_SCAN"

if [[ -f "$MANAGED_SETTINGS" ]]; then
  # Bare file/web tools and broad network/package runner allows remain release blockers.
  BROAD_ALLOWS="$(jq -r '.permissions.allow[]? | select(. == "Read" or . == "Edit" or . == "Write" or . == "Glob" or . == "Grep" or . == "WebFetch" or test("^Bash\\((git|gh|curl|wget|npm|pnpm|bun|npx|bunx|uv) \\*\\)$"))' "$MANAGED_SETTINGS" 2>/dev/null || true)"
  if [[ -n "$BROAD_ALLOWS" ]]; then
    while IFS= read -r rule; do fail "broad managed permission allow: '$rule'"; done <<< "$BROAD_ALLOWS"
  fi

  # Current Claude Code only supports path-scoped file policy through Read/Edit.
  UNSUPPORTED_RULES="$(jq -r '(.permissions.allow[]?, .permissions.ask[]?, .permissions.deny[]?) | select(test("^(Write|NotebookEdit|Glob)\\("))' "$MANAGED_SETTINGS" 2>/dev/null | sort -u || true)"
  if [[ -n "$UNSUPPORTED_RULES" ]]; then
    while IFS= read -r rule; do fail "unsupported path-scoped permission rule: '$rule'"; done <<< "$UNSUPPORTED_RULES"
  fi

  # Broad .git deny breaks index.lock creation after sandbox integration.
  GIT_BROAD_DENIES="$(jq -r '.permissions.deny[]? | select(test("^(Read|Edit)\\(\\.git/\\*\\*?\\)$"))' "$MANAGED_SETTINGS" 2>/dev/null || true)"
  if [[ -n "$GIT_BROAD_DENIES" ]]; then
    while IFS= read -r rule; do fail "git-workflow-breaking deny: '$rule'"; done <<< "$GIT_BROAD_DENIES"
  fi

  # bypassPermissions ignores permission allow rules. Keep Bash allows empty so
  # the dormant ruleset remains unambiguous if the owner later restores prompts.
  BASH_ALLOWS="$(jq -r '.permissions.allow[]? | select(startswith("Bash("))' "$MANAGED_SETTINGS" 2>/dev/null || true)"
  if [[ -n "$BASH_ALLOWS" ]]; then
    while IFS= read -r rule; do fail "managed Bash allow is forbidden: '$rule'"; done <<< "$BASH_ALLOWS"
  fi

  # Keep the dormant sandbox/WebFetch rules free of pre-approved domains so a
  # later return to sandboxed execution does not inherit an accidental allow.
  EFFECTIVE_DOMAINS="$(jq -r '[(.sandbox.network.allowedDomains[]? // empty), (.permissions.allow[]? | select(test("^WebFetch\\(domain:")) | sub("^WebFetch\\(domain:"; "") | sub("\\)$"; ""))] | .[]' "$MANAGED_SETTINGS" 2>/dev/null || true)"
  if [[ -n "$EFFECTIVE_DOMAINS" ]]; then
    while IFS= read -r dom; do fail "pre-allowed egress domain: '$dom'"; done <<< "$EFFECTIVE_DOMAINS"
  fi
fi

# Source PDF evidence is content-addressed; transcription must carry the same hash.
SOURCE_MANIFEST="$REPO_ROOT/docs/requirements/source-manifest.sha256"
TRANSCRIPTION="$REPO_ROOT/docs/requirements/requirements-transcription-260722.md"
if [[ ! -f "$SOURCE_MANIFEST" ]]; then
  fail "requirements source manifest missing: docs/requirements/source-manifest.sha256"
elif ! grep -Eq '^[0-9a-f]{64}[[:space:]]+260722_2151_001\.pdf$' "$SOURCE_MANIFEST"; then
  fail "requirements source manifest has invalid format"
else
  REQ_SHA="$(awk '{print $1}' "$SOURCE_MANIFEST")"
  if [[ ! -f "$TRANSCRIPTION" ]] || ! grep -qF "$REQ_SHA" "$TRANSCRIPTION"; then
    fail "requirements transcription does not reference source manifest SHA-256 $REQ_SHA"
  fi
fi

# =========================================================================
# 10. skill frontmatter schema(Agent Skills core spec)
#    name: 親directory名と一致・^[a-z0-9]+(-[a-z0-9]+)*$・64字以内
#    description: 必須・非空・1024字以内 / allowed-tools: 単一行space区切り(list・comma禁止)
# =========================================================================
echo "== 10. skill frontmatter schema =="
SKILL_SCHEMA_ERRORS="$(python3 - "$REPO_ROOT" <<'PYSCHEMA'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
errors = []
for pattern in (
    "claude/skills/*/SKILL.md",
    "codex/skills/*/SKILL.md",
    "shared/skills/*/SKILL.md",
    "shared/skills/claude-code/*/SKILL.md",
    "shared/skills/codex/*/SKILL.md",
):
    for sk in sorted(root.glob(pattern)):
        rel = sk.relative_to(root)
        text = sk.read_text(encoding="utf-8")
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not m:
            errors.append(f"{rel}: missing YAML frontmatter")
            continue
        fm = m.group(1).split("\n")
        fields = {}
        cur = None
        for line in fm:
            km = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):(.*)$", line)
            if km:
                cur = km.group(1)
                fields.setdefault(cur, []).append(km.group(2).strip())
            elif cur is not None:
                fields.setdefault(cur, []).append(line.strip())
        name = (fields.get("name") or [""])[0]
        expected_name = sk.parent.name
        if name != expected_name:
            errors.append(f"{rel}: name '{name}' != skill directory '{expected_name}'")
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name or "") or len(name) > 64:
            errors.append(f"{rel}: name '{name}' violates Agent Skills spec (a-z0-9, hyphen, <=64)")
        desc_lines = fields.get("description")
        if not desc_lines:
            errors.append(f"{rel}: description missing")
        else:
            desc = " ".join(l for l in desc_lines if l and l not in (">", "|", ">-", "|-"))
            if not desc.strip():
                errors.append(f"{rel}: description empty")
            elif len(desc) > 1024:
                errors.append(f"{rel}: description {len(desc)} chars > 1024")
        at = fields.get("allowed-tools")
        if at is not None:
            scalar = at[0]
            extra = [l for l in at[1:] if l]
            if not scalar or extra or scalar.startswith("-"):
                errors.append(f"{rel}: allowed-tools must be a single-line space-separated scalar (no YAML list)")
            elif "," in scalar:
                errors.append(f"{rel}: allowed-tools must be space-separated (no commas)")
print("\n".join(errors))
PYSCHEMA
)"
if [[ -n "$SKILL_SCHEMA_ERRORS" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "skill schema: $line"
  done <<< "$SKILL_SCHEMA_ERRORS"
fi

# =========================================================================
# 11. stale reference(削除・改名済み要素への参照がactive treeに残っていないか)
#     docs/・tests/・本validator自身は対象外(歴史的記述・fixture・deny-list定義のため)
# =========================================================================
echo "== 11. stale references in active tree =="
STALE_PATTERNS=(
  "/gh:(start|pr|issue|review|index|coderabbit)"
  "skills/issue-parser"
  "fast-worker|project-orchestrator|plan-reviewer-(completeness|critic|feasibility)|security-reviewer"
  "rules/(scope-discipline|framework-respect|git-safety)\.md"
  "test-quality-hook|user-prompt-submit-hook"
  "claude-bypass|bypass-profile|srt-bypass|bypass-gate"
)
while IFS= read -r f; do
  case "$f" in
    # measure-metrics.sh は改名前 layout の計測のため旧 path を意図的に参照する
    docs/* | tests/* | scripts/validate-layout.sh | scripts/measure-metrics.sh) continue ;;
  esac
  [[ -f "$f" ]] || continue
  for pat in "${STALE_PATTERNS[@]}"; do
    matches="$(grep -InoE "$pat" "$f" || true)"
    [[ -z "$matches" ]] && continue
    while IFS=: read -r lineno content; do
      fail "stale reference in $f:$lineno: $content"
    done <<< "$matches"
  done
done < <(git ls-files)

# =========================================================================
# 12. 直接実行される script の executable bit(適合性レビュー H-02)
#     CI は tests/test-*.sh を直接実行する。hook / bin / bootstrap も path 起動のため、
#     git mode 100755 でない tracked file は配布物として壊れている(exit 126)
# =========================================================================
echo "== 12. executable bits on direct-execution surfaces =="
NONEXEC="$(git ls-files -s -- 'tests/test-*.sh' 'scripts/*.sh' 'claude/hooks/*.sh' 'shared/bin/*' 'claude/bin/*' bootstrap.sh 2>/dev/null | awk '$1 != "100755" {print $1 " " $4}' || true)"
if [[ -n "$NONEXEC" ]]; then
  while IFS= read -r entry; do
    fail "non-executable direct-execution script: $entry(git update-index --chmod=+x で 100755 にする — H-02)"
  done <<< "$NONEXEC"
fi

echo
if [[ "$violations" -eq 0 ]]; then
  echo "PASS: no layout violations found"
  exit 0
fi
echo "FAIL: $violations violation(s) found" >&2
exit 1
