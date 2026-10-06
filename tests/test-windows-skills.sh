#!/usr/bin/env bash
# test-windows-skills.sh — bootstrap.sh --windows-{dry-run,apply,check} と scripts/windows-skills.py。
# Claude desktop app (Windows) 向け skill copy の変換（helper 呼び出しの WSL 化・marker）、
# 冪等な apply、手書き directory・手編集の保護、source 変更と一覧から外した skill の drift 検出、
# 管理外 directory を触らないこと、配布表の validate を、sandbox の target で確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
expect_rc() { # desc want_rc cmd...
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" >"$SANDBOX/out" 2>"$SANDBOX/err" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (rc=$rc, want $want): $(cat "$SANDBOX/out" "$SANDBOX/err")"; fi
}
tree_sum() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum); }

export HOME="$SANDBOX/home"
mkdir -p "$HOME"
export AGENTS_TOOLKIT_WSL_DISTRO="TestDistro"
unset AGENTS_TOOLKIT_WINDOWS_CLAUDE_DIR

# 変更系の確認用に、配布に必要な部分だけを持つ repo copy を作る（実 repo は書き換えない）
REPO="$SANDBOX/repo"
mkdir -p "$REPO/scripts" "$REPO/shared/skills"
cp "$REPO_ROOT/bootstrap.sh" "$REPO/"
cp "$REPO_ROOT/scripts/windows-skills.py" "$REPO/scripts/"
cp -r "$REPO_ROOT/install" "$REPO/install"
mkdir -p "$REPO/claude"
cp -r "$REPO_ROOT/claude/bin" "$REPO_ROOT/claude/skills" "$REPO/claude/"
cp -r "$REPO_ROOT/shared/skills/article-style" "$REPO/shared/skills/"
BOOT="$REPO/bootstrap.sh"

T="$SANDBOX/win/.claude"
mkdir -p "$T/skills/my-own-skill"
printf -- '---\nname: my-own-skill\ndescription: hand made\n---\n' > "$T/skills/my-own-skill/SKILL.md"
printf '{"theme":"dark"}\n' > "$T/settings.json"
OWN_BEFORE="$(tree_sum "$T/skills/my-own-skill")"
SETTINGS_BEFORE="$(sha256sum < "$T/settings.json")"

# ---- 配布表の検証（実 repo）----------------------------------------------------------------------
expect_rc "validate: 実 repo の install/windows-skills.tsv が変換できる" 0 python3 "$REPO_ROOT/scripts/windows-skills.py" validate
mapfile -t LISTED < <(awk -F'\t' '!/^#/ && NF == 3 {print $1}' "$REPO_ROOT/install/windows-skills.tsv")
[[ " ${LISTED[*]} " == *" grok-digest "* ]] && ok "grok-digest は Windows 配布対象" || ng "grok-digest が install/windows-skills.tsv にない"

# ---- dry-run は何も書かない ------------------------------------------------------------------------
expect_rc "dry-run: exit 0" 0 "$BOOT" --windows-dry-run --windows-target "$T"
grep -q "would create: $T/skills/grok-digest" "$SANDBOX/out" && ok "dry-run: grok-digest を作成予定として列挙" || ng "dry-run output: $(cat "$SANDBOX/out")"
[[ ! -e "$T/skills/grok-digest" ]] && ok "dry-run: 何も作らない" || ng "dry-run created files"
expect_rc "check: 未配布は drift (exit 1)" 1 "$BOOT" --windows-check --windows-target "$T"

# ---- apply -------------------------------------------------------------------------------------
expect_rc "apply: exit 0" 0 "$BOOT" --windows-apply --windows-target "$T"
for s in "${LISTED[@]}"; do
  [[ -f "$T/skills/$s/SKILL.md" && -f "$T/skills/$s/.agents-toolkit-generated.json" ]] && ok "apply: $s を marker 付きで配布" || ng "apply: $s missing"
done
G="$T/skills/grok-digest"
[[ "$(head -1 "$G/SKILL.md")" == "---" ]] && grep -qx 'name: grok-digest' "$G/SKILL.md" && ok "SKILL.md: frontmatter が先頭のまま、name も同じ" || ng "SKILL.md frontmatter broken"
grep -q 'Do not edit by hand' "$G/SKILL.md" && grep -q 'Do not edit by hand' "$G/references/workflow.md" && ok "Markdown に「手で編集しない」marker" || ng "marker comment missing"
grep -q '^## Windows (Claude desktop app)$' "$G/SKILL.md" && ok "helper を使う skill に Windows 実行規則の節" || ng "Windows section missing"
grep -q "wsl -d TestDistro -- bash -lc '~/.claude/bin/grok-digest select --days <days>'" "$G/SKILL.md" && ok "helper 名だけの呼び出しを WSL 経由の full path に変換" || ng "bare helper call not converted"
grep -q "^   wsl -d TestDistro -- bash -lc '~/.claude/bin/grok-digest answer " "$G/references/workflow.md" && ok "code block 行を indent を保って変換" || ng "fenced call not converted"
if grep -rnE '(^|[^'"'"'])~/\.claude/bin/' "$G" "$T/skills/cross-critic" --include='*.md' | grep -v "bash -lc '~/.claude/bin/" >/dev/null; then
  ng "未変換の ~/.claude/bin 呼び出しが残っている: $(grep -rnE '~/\.claude/bin/' "$G" "$T/skills/cross-critic" --include='*.md' | grep -v "bash -lc '~/.claude/bin/" | head -3)"
else
  ok "~/.claude/bin の呼び出しは全て WSL 経由"
fi
grep -q "MSYS_NO_PATHCONV=1" "$G/SKILL.md" && grep -q "wsl -d TestDistro -e wslpath -a" "$G/SKILL.md" && ok "Windows 節: Git Bash の path 変換抑止と wslpath -e" || ng "Windows section guidance missing"
! grep -q '^## Windows' "$T/skills/article-style/SKILL.md" && ok "helper の無い skill には Windows 節を足さない" || ng "article-style got a Windows section"
python3 - "$G/.agents-toolkit-generated.json" <<'PY' && ok "marker JSON: skill・source・commit・generated_at・files" || ng "marker JSON fields"
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
assert m["skill"] == "grok-digest" and m["source"] == "claude/skills/grok-digest"
assert m["commit"] and m["generated_at"] and m["distro"] == "TestDistro" and "SKILL.md" in m["files"]
assert "Do not edit" in m["notice"]
PY
[[ "$(tree_sum "$T/skills/my-own-skill")" == "$OWN_BEFORE" && "$(sha256sum < "$T/settings.json")" == "$SETTINGS_BEFORE" ]] && ok "管理外の skill と settings.json は触らない" || ng "unmanaged files changed"

expect_rc "check: 配布直後は PASS" 0 "$BOOT" --windows-check --windows-target "$T"
MARKER_BEFORE="$(sha256sum < "$G/.agents-toolkit-generated.json")"
expect_rc "apply: 2回目も exit 0" 0 "$BOOT" --windows-apply --windows-target "$T"
grep -q "^ok: $G$" "$SANDBOX/out" && [[ "$(sha256sum < "$G/.agents-toolkit-generated.json")" == "$MARKER_BEFORE" ]] && ok "apply は冪等（内容が同じなら書き換えない）" || ng "second apply rewrote: $(cat "$SANDBOX/out")"

# ---- 手編集の保護 ------------------------------------------------------------------------------
echo "local edit" >> "$G/references/note-format.md"
EDITED="$(tree_sum "$G")"
expect_rc "check: 手編集を drift として検出" 1 "$BOOT" --windows-check --windows-target "$T"
grep -q 'references/note-format.md' "$SANDBOX/out" && ok "check: 変更されたファイル名を報告" || ng "check did not name the edited file: $(cat "$SANDBOX/out")"
expect_rc "apply: 手編集があれば停止" 1 "$BOOT" --windows-apply --windows-target "$T"
[[ "$(tree_sum "$G")" == "$EDITED" ]] && ok "apply: 手編集を上書きしない" || ng "apply overwrote a hand edit"
rm -rf "$G"
expect_rc "apply: 消した skill を再生成" 0 "$BOOT" --windows-apply --windows-target "$T"

# ---- 手書き directory の保護（preflight で全体を止める） -------------------------------------------
T2="$SANDBOX/win2/.claude"
mkdir -p "$T2/skills/grok-digest"
printf 'hand made\n' > "$T2/skills/grok-digest/SKILL.md"
expect_rc "apply: marker の無い既存 directory があれば停止" 1 "$BOOT" --windows-apply --windows-target "$T2"
[[ "$(cat "$T2/skills/grok-digest/SKILL.md")" == "hand made" && ! -e "$T2/skills/cross-critic" ]] && ok "apply: 手書きを残し、他の skill も書かない" || ng "apply wrote despite a hand-made directory"
expect_rc "check: 手書き directory は drift" 1 "$BOOT" --windows-check --windows-target "$T2"
expect_rc "target が無ければ停止" 1 "$BOOT" --windows-apply --windows-target "$SANDBOX/missing/.claude"
[[ ! -e "$SANDBOX/missing" ]] && ok "存在しない target を作らない" || ng "missing target was created"
expect_rc "--windows-target だけでは拒否" 1 "$BOOT" --check --windows-target "$T"
mkdir "$T/skills/.agents-toolkit-staging-grok-digest"
expect_rc "apply: 前回の作業 directory が残っていれば停止" 1 "$BOOT" --windows-apply --windows-target "$T"
rmdir "$T/skills/.agents-toolkit-staging-grok-digest"

# ---- source の変更・一覧からの削除 ---------------------------------------------------------------
printf '\nNew line from the source.\n' >> "$REPO/claude/skills/grok-digest/references/workflow.md"
expect_rc "check: source 変更を drift として検出" 1 "$BOOT" --windows-check --windows-target "$T"
grep -q 'references/workflow.md' "$SANDBOX/out" && ok "check: 変わるファイルを報告" || ng "check output: $(cat "$SANDBOX/out")"
expect_rc "apply: source 変更を反映" 0 "$BOOT" --windows-apply --windows-target "$T"
grep -q "^updated: $G " "$SANDBOX/out" && grep -q 'New line from the source.' "$G/references/workflow.md" && ok "apply: 更新した" || ng "update not applied: $(cat "$SANDBOX/out")"
[[ -z "$(find "$T/skills" -maxdepth 1 -name '.agents-toolkit-staging-*')" ]] && ok "apply: 作業 directory を残さない" || ng "staging left behind"
expect_rc "check: 反映後は PASS" 0 "$BOOT" --windows-check --windows-target "$T"

grep -v '^article-style' "$REPO/install/windows-skills.tsv" > "$SANDBOX/list" && cp "$SANDBOX/list" "$REPO/install/windows-skills.tsv"
expect_rc "check: 一覧から外した生成物は drift" 1 "$BOOT" --windows-check --windows-target "$T"
expect_rc "apply: 一覧から外した生成物を削除" 0 "$BOOT" --windows-apply --windows-target "$T"
[[ ! -e "$T/skills/article-style" && "$(tree_sum "$T/skills/my-own-skill")" == "$OWN_BEFORE" ]] && ok "apply: 外した skill だけを削除し管理外は残す" || ng "orphan removal wrong"
expect_rc "check: 削除後は PASS" 0 "$BOOT" --windows-check --windows-target "$T"

# ---- 配布表の不備 ------------------------------------------------------------------------------
cp "$REPO/install/windows-skills.tsv" "$SANDBOX/list.orig"
sed -i 's/^grok-digest\t\(.*\)\t.*$/grok-digest\t\1\tgrok-digest/' "$REPO/install/windows-skills.tsv"
expect_rc "validate: 宣言されていない helper の呼び出しを拒否" 1 python3 "$REPO/scripts/windows-skills.py" validate
grep -q 'private-routing-locate' "$SANDBOX/err" && ok "validate: 未宣言の helper 名を報告" || ng "validate err: $(cat "$SANDBOX/err")"
cp "$SANDBOX/list.orig" "$REPO/install/windows-skills.tsv"
printf 'gh-finish\tclaude/skills/gh-finish\tno-such-helper\n' >> "$REPO/install/windows-skills.tsv"
expect_rc "validate: claude/bin に無い helper を拒否" 1 python3 "$REPO/scripts/windows-skills.py" validate
cp "$SANDBOX/list.orig" "$REPO/install/windows-skills.tsv"
printf 'grok-digest-x\tclaude/skills/grok-digest\t-\n' >> "$REPO/install/windows-skills.tsv"
expect_rc "validate: manifest で配布していない source を拒否" 1 python3 "$REPO/scripts/windows-skills.py" validate
cp "$SANDBOX/list.orig" "$REPO/install/windows-skills.tsv"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: test-windows-skills"
  exit 0
fi
echo "FAIL: $FAILURES check(s) failed" >&2
exit 1
