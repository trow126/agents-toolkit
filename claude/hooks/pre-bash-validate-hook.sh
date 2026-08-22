#!/bin/bash
# PreToolUse hook: validate Agent lifecycle and Bash commands (fail-closed).
#
# 位置づけ(重要):
#   本 hook は raw command string に対する quote 正規化つき heuristic であり、
#   「事故と平易な迂回の防止層」である。shell 評価後の argv は解析しない(できない)ため、
#   security boundary としては扱わない。現行 owner policy は bypassPermissions かつ
#   sandbox 無効のため、permission deny/ask や OS-level sandbox という下位境界はない。
#   project-policy-gate と本 hook の literal 検査は事故防止として exit 2 で block するが、
#   runtime 構築 path や未知の迂回を完全には遮断しない。
#
# 方針:
#   - fail-closed: 入力の parse 失敗・依存欠落・schema 不一致は exit 2(block)
#   - 検査は quote 除去後の文字列(NORM)に対して行う(`--am""end` の類を吸収)
#   - runtime 構築 path(base64 復号や変数連結で literal が現れないもの)は本 hook の対象外
# exit 2 = block(stderr が理由)。それ以外の非ゼロは non-blocking のため、
# block 意図の失敗はすべて明示的に exit 2 へ変換する。
set -euo pipefail

block() {
    echo "Blocked: $*" >&2
    exit 2
}

# 依存欠落は fail-closed(検査できないコマンドを通さない)
command -v jq >/dev/null 2>&1 || block "pre-bash-validate-hook requires jq but it is not installed (fail-closed)"

INPUT=$(cat) || block "failed to read hook input (fail-closed)"

# JSON objectであり、登録matcherに対応するtool_nameであることを厳格検証する。
if ! echo "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    block "hook input is not valid JSON (fail-closed)"
fi
if ! TOOL_NAME=$(echo "$INPUT" | jq -er \
    '.tool_name | select(type == "string" and length > 0)' 2>/dev/null); then
    block "hook input has no non-empty tool_name (fail-closed)"
fi

# nested Agent内のCodex processは、600秒後のBash自動background化で
# completion ownerが終了済みAgentに残る。main sessionから直接起動させる。
if [[ "$TOOL_NAME" == "Agent" ]]; then
    if ! SUBAGENT_TYPE=$(echo "$INPUT" | jq -er \
        '.tool_input.subagent_type | select(type == "string" and length > 0)' \
        2>/dev/null); then
        block "hook input has no non-empty tool_input.subagent_type (fail-closed)"
    fi
    if [[ "$SUBAGENT_TYPE" == "codex:codex-rescue" ]]; then
        block "codex:codex-rescue Agent 経由の委任を拒否した。10分超過時にCodex processが終了済みAgentへdetachされ、main sessionへ完了通知が届かないため。main sessionから codex-companion.mjs task を直接 Bash(run_in_background=true) で起動し、Claude main sessionをcompletion ownerにすること"
    fi
    exit 0
fi
if [[ "$TOOL_NAME" != "Bash" ]]; then
    block "hook input has an unexpected tool_name (fail-closed)"
fi

# matcher=Bashではtool_input.commandを取り出せない入力をschema違反としてblockする。
# agent_type は main session では省略可能だが、存在する場合は string でなければならない。
# Bash tool の run_in_background も省略可能だが、存在する場合は boolean に限定する。
if ! COMMAND=$(echo "$INPUT" | jq -er '.tool_input.command | select(type == "string" and length > 0)' 2>/dev/null); then
    block "hook input has no non-empty tool_input.command (fail-closed)"
fi
if ! AGENT_TYPE=$(echo "$INPUT" | jq -er '
    if has("agent_type") then
        .agent_type | select(type == "string")
    else
        ""
    end
' 2>/dev/null); then
    block "hook input agent_type must be a string when present (fail-closed)"
fi
if ! RUN_IN_BACKGROUND=$(echo "$INPUT" | jq -er '
    if (.tool_input | has("run_in_background")) then
        .tool_input.run_in_background
        | select(type == "boolean")
        | if . then "true" else "false" end
    else
        "false"
    end
' 2>/dev/null); then
    block "hook input tool_input.run_in_background must be a boolean when present (fail-closed)"
fi

# Project/local settings are lower precedence than managed settings, but some
# array surfaces (notably sandbox.excludedCommands) have no dedicated managed
# only-switch.  Resolve the installed gate first; tests/repository execution use
# the source-tree sibling after resolving this hook's symlink.
HOOK_CWD=$(echo "$INPUT" | jq -r '(.cwd // .tool_input.cwd // "") | if type == "string" then . else "" end' 2>/dev/null) ||     block "hook input cwd cannot be parsed (fail-closed)"
[[ -n "$HOOK_CWD" ]] || HOOK_CWD="$PWD"
HOOK_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)" || block "cannot resolve hook directory"
PROJECT_POLICY_GATE="$HOOK_DIR/../bin/project-policy-gate"
[[ -x "$PROJECT_POLICY_GATE" ]] || block "project-policy-gate is missing or not executable: $PROJECT_POLICY_GATE"
if ! GATE_OUTPUT=$("$PROJECT_POLICY_GATE" --cwd "$HOOK_CWD" --quiet 2>&1); then
    block "unsafe project/local Claude settings: $GATE_OUTPUT"
fi

# quote 正規化: `--am""end` / `'.e'nv` のような quote 分割 literal を復元する。
# \042 = double quote, \047 = single quote
NORM=$(printf '%s' "$COMMAND" | tr -d '\042\047')

# codex:codex-rescue 内で companion task を起動すると、foreground でも600秒経過時に
# Bash runtimeがprocessをbackgroundへ移し、rescue Agent終了後の完了通知がmain sessionへ
# 届かない。agent_type と companion task の共起に限定して全実行をfail-closedにし、
# main sessionがBash(run_in_background=true)で直接completion ownerになるよう強制する。
# raw command に対する heuristic なので、対象 agent 内では過剰側に倒す。
if [[ "$AGENT_TYPE" == "codex:codex-rescue" ]]; then
    if printf '%s' "$NORM" | grep -qE '(^|[^A-Za-z0-9_.-])codex-companion\.mjs([^A-Za-z0-9_.-]|$)' &&
        printf '%s' "$NORM" | grep -qE '(^|[^A-Za-z0-9_-])task([^A-Za-z0-9_-]|$)'; then
        block "codex:codex-rescue 内の companion task 起動を拒否した。foregroundでも600秒後にdetachして完了通知を失うため、Claude main sessionから codex-companion.mjs task を直接 Bash(run_in_background=true) で起動すること"
    fi
fi

# Block writes to block devices
if printf '%s' "$NORM" | grep -qE '(>|of=)\s*/dev/sd'; then
    block "write to block device detected in command"
fi

# Block mkfs on block devices
if printf '%s' "$NORM" | grep -qE 'mkfs\S*\s+/dev/sd'; then
    block "mkfs on block device detected"
fi

# git commit --amend の deny(H-011: 共起判定)。
# 旧実装の「git ... commit の直後関係」を要求する 2 段 regex は alias(`git -c alias.ci=commit ci`)や
# nested shell(`sh -c "git commit --amend"`)で素通しになったため、
# 「git という語」と「--amend という token」の共起で拒否する(order/位置に非依存)。
# `x=--amend; git commit "$x"` のような変数代入形も literal を含むため対象になる。
# 過剰側に倒れる設計(例: `git log` と文字列 "--amend" の共存も block)であり、
# under-block より安全。history rewrite が必要な場合はユーザーが手動実行する。
if printf '%s' "$NORM" | grep -qE '(^|[^A-Za-z0-9_])git([^A-Za-z0-9_]|$)'; then
    if printf '%s' "$NORM" | grep -qE '(^|[^A-Za-z0-9_])--amend([^A-Za-z0-9_]|$)'; then
        block "git と --amend の共起は deny-by-policy (history rewrite guard)。必要な場合はユーザーが手動実行するか明示承認を得ること"
    fi
fi

# Block .env content reads while allowing existence checks.
# 事故防止層: literal(quote 分割含む)の .env 読み取りを block する。
# runtime 構築 path は本 hook の対象外であり、sandbox 無効時は別の下位境界もない。
# path-aware: 先頭・区切り文字・"/" の直後の .env を対象にする(nested `config/.env` を含む — H-014)
if printf '%s' "$NORM" | grep -qE '(^|[^A-Za-z0-9._-])\.env([.-][A-Za-z0-9_.-]+)?([^A-Za-z0-9._-]|$)'; then
    # Dangerous readers: anything that emits file contents or sources them.
    # NOTE: dot builtin(source)をここに `\.` で入れると `\b\.\b` が
    # settings.json 等の word.word の任意 dot に一致し偽陽性を量産するため、
    # 下の command-position 限定チェックで扱う。
    if printf '%s' "$NORM" | grep -qE '\b(cat|tac|rev|nl|pr|fold|fmt|head|tail|less|more|view|vi|vim|nano|emacs|ed|open|awk|gawk|sed|cut|sort|uniq|tr|column|paste|join|comm|od|xxd|hexdump|strings|base64|base32|grep|egrep|fgrep|zgrep|rg|ag|ack|python|python3|uv|uvw|node|bun|deno|ruby|perl|php|bash|sh|zsh|source|tee|dd|cp|mv|install|rsync|scp|gzip|gunzip|zcat|bzcat|xzcat|tar|jar|unzip|diff|cmp|vimdiff|colordiff|wc|readlink|file)\b'; then
        block "command appears to read .env content. For existence check, use Glob, ls, stat, or test."
    fi
    # dot builtin(`. .env` / `true; . config/.env`): 行頭または区切り直後の
    # standalone `.` token のみを source とみなす。
    if printf '%s' "$NORM" | grep -qE '(^|[;&|(`])[[:space:]]*\.[[:space:]]'; then
        block "command appears to source .env via the dot builtin"
    fi
    # Redirection reading from .env: `cmd < .env`, `while read < config/.env`
    if printf '%s' "$NORM" | grep -qE '<\s*[^ ;|&]*\.env([.-][A-Za-z0-9_.-]+)?(\s|$)'; then
        block "input redirection from .env detected"
    fi
    # Command substitution or process substitution targeting .env
    if printf '%s' "$NORM" | grep -qE '(\$\(|<\(|`)[^)]*\.env'; then
        block "command/process substitution targeting .env detected"
    fi
fi

exit 0
