#!/usr/bin/env bash
# pursue-goal と pursue-stop-hook: 完了条件が未達なら Stop を exit 2 で取り消し、達成・上限到達・
# 別 session・解除では止める。check は pre-bash gate を通し、異常は exit 1（non-blocking）にする。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/claude/bin/pursue-goal"
HOOK="$REPO_ROOT/claude/hooks/pursue-stop-hook.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

export HOME="$SANDBOX/home"
export XDG_STATE_HOME="$SANDBOX/state"
mkdir -p "$HOME"
PROJECT="$SANDBOX/project"
mkdir -p "$PROJECT/sub"
git -C "$PROJECT" init -q
PROJECT="$(cd "$PROJECT" && pwd -P)"
STATE_DIR="$XDG_STATE_HOME/agents-toolkit/pursue"
HISTORY="$STATE_DIR/history.jsonl"

helper() { (cd "$PROJECT" && "$HELPER" "$@"); }
hook() {
  local session="$1" cwd="${2:-$PROJECT}"
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$session" "$cwd" | "$HOOK"
}
run_hook() {
  RC=0
  OUT="$(hook "$@" 2>&1)" || RC=$?
}
active_count() { find "$STATE_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l; }
last_event() { tail -n 1 "$HISTORY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["event"])'; }

# 1. goal なしでは何もしない
run_hook s1
if [[ "$RC" -eq 0 && -z "$OUT" ]]; then ok "goal なしでは exit 0"; else ng "goal なし: rc=$RC out=$OUT"; fi

# 2. 達成済みの check は停止を許可し、goal を閉じる
helper set --check 'true' >/dev/null
run_hook s1
if [[ "$RC" -eq 0 && "$(active_count)" -eq 0 && "$(last_event)" == achieved ]]; then
  ok "check pass で exit 0、goal を achieved で閉じる"
else
  ng "check pass: rc=$RC active=$(active_count) out=$OUT"
fi

# 3. 未達なら exit 2 で取り消し、理由と出力末尾を返す。最初の Stop が session を束縛する
helper set --check 'echo fixture-output; exit 3' --max-stops 2 >/dev/null
run_hook s1
if [[ "$RC" -eq 2 && "$OUT" == *"1/2"* && "$OUT" == *"exit 3"* && "$OUT" == *fixture-output* && "$OUT" == *"pursue-goal clear"* ]]; then
  ok "未達で exit 2、回数・exit code・出力・解除方法を返す"
else
  ng "未達: rc=$RC out=$OUT"
fi
if helper status | grep -q '"session_id": "s1"'; then ok "最初の Stop が session を束縛する"; else ng "session 束縛: $(helper status)"; fi

# 4. 別 session には影響しない
run_hook s2
if [[ "$RC" -eq 0 && -z "$OUT" ]]; then ok "別 session の Stop は止めない"; else ng "別 session: rc=$RC out=$OUT"; fi

# 5. subdirectory の cwd も同じ git root の goal を見る
run_hook s1 "$PROJECT/sub"
if [[ "$RC" -eq 2 && "$OUT" == *"2/2"* ]]; then ok "subdirectory からも同じ goal を強制する"; else ng "subdirectory: rc=$RC out=$OUT"; fi

# 6. 上限到達で未達のまま停止を許可し、goal を閉じる
run_hook s1
if [[ "$RC" -eq 1 && "$OUT" == *"上限"* && "$(active_count)" -eq 0 && "$(last_event)" == budget_exhausted ]]; then
  ok "上限到達で exit 1（non-blocking）、budget_exhausted で閉じる"
else
  ng "上限到達: rc=$RC active=$(active_count) out=$OUT"
fi

# 7. 重複登録は拒否、--replace で置き換え、clear は理由必須で閉じる
helper set --check 'false' >/dev/null
rc=0; helper set --check 'false' >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 ]]; then ok "重複登録を拒否する"; else ng "重複登録 rc=$rc"; fi
if helper set --check 'exit 4' --replace >/dev/null && helper status | grep -q 'exit 4'; then
  ok "--replace で置き換える"
else
  ng "--replace"
fi
rc=0; helper clear --reason '' >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 && "$(active_count)" -eq 1 ]]; then ok "空の理由では解除しない"; else ng "空の理由 rc=$rc"; fi
if helper clear --reason 'fixture' >/dev/null && [[ "$(active_count)" -eq 0 && "$(last_event)" == cleared ]]; then
  ok "clear で閉じて理由を履歴に残す"
else
  ng "clear"
fi
run_hook s1
if [[ "$RC" -eq 0 ]]; then ok "解除後は停止を許可する"; else ng "解除後 rc=$RC"; fi

# 8. pre-bash gate が拒否する check は登録できない
rc=0; err="$(helper set --check 'cat .env' 2>&1 >/dev/null)" || rc=$?
if [[ "$rc" -eq 1 && "$err" == *"pre-bash gate"* && "$(active_count)" -eq 0 ]]; then
  ok "pre-bash gate が拒否する check は登録しない"
else
  ng "gate 拒否: rc=$rc err=$err"
fi

# 9. 登録後に書き換えられた check も実行前に gate を通し、拒否なら強制を解除する
helper set --check 'false' >/dev/null
state_file="$(find "$STATE_DIR" -maxdepth 1 -name '*.json')"
python3 - "$state_file" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["check"] = "cat .env"; json.dump(d, open(p, "w"))
PY
run_hook s1
if [[ "$RC" -eq 1 && "$OUT" == *"拒否"* && "$(active_count)" -eq 0 && "$(last_event)" == rejected ]]; then
  ok "改ざんされた check は実行せず rejected で閉じる"
else
  ng "改ざん check: rc=$RC out=$OUT"
fi

# 10. timeout は未達として扱い、孫 process を残しても hook は待たずに返る
helper set --check 'sleep 30 & sleep 30' --timeout 1 >/dev/null
start=$SECONDS
run_hook s1
elapsed=$((SECONDS - start))
if [[ "$RC" -eq 2 && "$OUT" == *"timed out after 1s"* && "$elapsed" -le 10 ]]; then
  ok "timeout を未達として扱い、${elapsed}s で返る"
else
  ng "timeout: rc=$RC elapsed=${elapsed}s out=$OUT"
fi
helper clear --reason 'fixture' >/dev/null

# 11. 壊れた state は exit 1（non-blocking）で報告し、session を閉じ込めない
helper set --check 'false' >/dev/null
state_file="$(find "$STATE_DIR" -maxdepth 1 -name '*.json')"
printf '{broken' > "$state_file"
run_hook s1
if [[ "$RC" -eq 1 && "$OUT" == *"unreadable state file"* ]]; then ok "壊れた state は exit 1 で報告する"; else ng "壊れた state: rc=$RC out=$OUT"; fi
rm -f "$state_file"

# 12. 不正な hook 入力も exit 1
RC=0; OUT="$(printf 'not json' | "$HOOK" 2>&1)" || RC=$?
if [[ "$RC" -eq 1 && "$OUT" == *"not JSON"* ]]; then ok "不正な hook 入力は exit 1"; else ng "不正入力: rc=$RC out=$OUT"; fi

# 13. managed settings の Stop に登録され、timeout は check 上限より長い
if python3 - "$REPO_ROOT/claude/managed-settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
hooks = [h for g in d["hooks"]["Stop"] for h in g["hooks"] if h["command"] == "~/.claude/hooks/pursue-stop-hook.sh"]
sys.exit(0 if len(hooks) == 1 and hooks[0]["timeout"] > 540 else 1)
PY
then ok "managed Stop hook に timeout > 540 で登録済み"; else ng "managed Stop hook 登録"; fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "all pursue-goal tests passed"
