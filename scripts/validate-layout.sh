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
ALLOWLIST_EXACT=("claude/.gitignore" "claude/README.md")
ALLOWLIST_PREFIX=("claude/githooks/")

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
# 8. 危険設定(waiverなしでは致命)
#    共有既定にbypass/unsandboxed/full model pinを残す場合は
#    docs/waivers/settings-waivers.tsv に file<TAB>pattern<TAB>environment<TAB>expires<TAB>reason
#    の有効行(expires >= today)が必要。waiver済みはWARN、未waiverはFAIL。
# =========================================================================
echo "== 8. dangerous settings (fatal without waiver) =="
WAIVER_FILE="$REPO_ROOT/docs/waivers/settings-waivers.tsv"
WAIVER_ENVS="$REPO_ROOT/docs/waivers/environments.txt"
TODAY="$(date +%F)"

# waiver file 自体の schema 検査(H-008): 5列・全列非空・実在日・承認済み environment のみ許可。
# 不正行は「使われていなくても」違反として列挙する(governance gate の腐敗防止)。
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
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: 空の列がある(environment/reason 含め全列必須)"
    if [[ ! "$wexpires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -d "$wexpires" +%F >/dev/null 2>&1 || [[ "$(date -d "$wexpires" +%F)" != "$wexpires" ]]; then
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: expires が実在日の YYYY-MM-DD ではない: '$wexpires'"
    fi
    if [[ -n "$wenv" ]] && { [[ ! -f "$WAIVER_ENVS" ]] || ! grep -qxF "$wenv" <(grep -v '^#' "$WAIVER_ENVS"); }; then
      fail "waiver schema: docs/waivers/settings-waivers.tsv:$wl: 未承認 environment '$wenv'(docs/waivers/environments.txt の allowlist に追加が必要)"
    fi
  done < "$WAIVER_FILE"
fi
declare -a DANGER_PATTERNS=(
  "bypassPermissions|bypassPermissions"
  "danger-full-access|danger-full-access"
  "skipDangerousModePermissionPrompt|\"skipDangerousModePermissionPrompt\"[[:space:]]*:[[:space:]]*true"
  "allowUnsandboxedCommands|\"allowUnsandboxedCommands\"[[:space:]]*:[[:space:]]*true"
)
has_waiver() {
  local file="$1" pname="$2"
  [[ -f "$WAIVER_FILE" ]] || return 1
  while IFS=$'\t' read -r wfile wpattern wenv wexpires wreason; do
    [[ "$wfile" == \#* || -z "$wfile" ]] && continue
    # schema-valid な行だけを waiver として認める(非空5列・実在日・承認済み environment)
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
for f in claude/settings.json codex/config.toml codex/gh.config.toml; do
  [[ -f "$f" ]] || continue
  for entry in "${DANGER_PATTERNS[@]}"; do
    pname="${entry%%|*}"
    pregex="${entry#*|}"
    matches="$(grep -InoE "$pregex" "$f" || true)"
    [[ -z "$matches" ]] && continue
    while IFS=: read -r lineno content; do
      if has_waiver "$f" "$pname"; then
        warn "$f:$lineno: $content (waived: see docs/waivers/settings-waivers.tsv)"
      else
        fail "dangerous setting without waiver: $f:$lineno: $content (add waiver row to docs/waivers/settings-waivers.tsv or remove)"
      fi
    done <<< "$matches"
  done
done

# full model pin は構造的 scanner で検査する(quoted YAML / literal TOML 対応。measure-metrics と共有 — H-001)
PIN_SCAN="$(python3 "$SCRIPT_DIR/lib/scan-model-pins.py" "$REPO_ROOT" 2>&1)" || fail "model pin scan failed: $PIN_SCAN"
while IFS=: read -r pfile pline pkind pvalue; do
  [[ "$pkind" == "pin" ]] || continue
  if has_waiver "$pfile" "full-model-pin"; then
    warn "$pfile:$pline: model=$pvalue (waived: see docs/waivers/settings-waivers.tsv)"
  else
    fail "dangerous setting without waiver: $pfile:$pline: full model pin '$pvalue' (add waiver row to docs/waivers/settings-waivers.tsv or use a tier alias)"
  fi
done <<< "$PIN_SCAN"

# broad permission allow の検査(H-007): bare file/web tool と広域 Bash wildcard を release blocker にする
if [[ -f claude/settings.json ]]; then
  BROAD_ALLOWS="$(jq -r '.permissions.allow[]? | select(. == "Read" or . == "Edit" or . == "Write" or . == "Glob" or . == "Grep" or . == "WebFetch" or (test("^Bash\\((git|gh|curl|wget) \\*\\)$")))' claude/settings.json)"
  if [[ -n "$BROAD_ALLOWS" ]]; then
    while IFS= read -r rule; do
      if has_waiver "claude/settings.json" "broad-allow"; then
        warn "claude/settings.json: broad allow '$rule' (waived)"
      else
        fail "dangerous setting without waiver: claude/settings.json: broad permission allow '$rule' (path/subcommand-scoped rule に置換するか waiver を登録)"
      fi
    done <<< "$BROAD_ALLOWS"
  fi
fi

# =========================================================================
# 9. skill frontmatter schema(Agent Skills core spec)
#    name: 親directory名と一致・^[a-z0-9]+(-[a-z0-9]+)*$・64字以内
#    description: 必須・非空・1024字以内 / allowed-tools: 単一行space区切り(list・comma禁止)
# =========================================================================
echo "== 9. skill frontmatter schema =="
SKILL_SCHEMA_ERRORS="$(python3 - "$REPO_ROOT" <<'PYSCHEMA'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
errors = []
for pattern in ("claude/skills/*/SKILL.md", "codex/skills/*/SKILL.md", "shared/skills/*/SKILL.md"):
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
        if name != sk.parent.name:
            errors.append(f"{rel}: name '{name}' != directory '{sk.parent.name}'")
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
# 10. stale reference(削除・改名済み要素への参照がactive treeに残っていないか)
#     docs/・tests/・本validator自身は対象外(歴史的記述・fixture・deny-list定義のため)
# =========================================================================
echo "== 10. stale references in active tree =="
STALE_PATTERNS=(
  "/gh:(start|pr|issue|review|index|coderabbit)"
  "skills/issue-parser"
  "fast-worker|project-orchestrator|plan-reviewer-(completeness|critic|feasibility)|security-reviewer"
  "rules/(scope-discipline|framework-respect|git-safety)\.md"
  "test-quality-hook|user-prompt-submit-hook"
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

echo
if [[ "$violations" -eq 0 ]]; then
  echo "PASS: no layout violations found"
  exit 0
fi
echo "FAIL: $violations violation(s) found" >&2
exit 1
