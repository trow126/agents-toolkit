#!/bin/bash
# PreToolUse hook: validate Bash commands before execution (fail-closed — 2026-07-23 H-014/H-011)
#
# 方針:
#   - security hook は fail-closed: 入力の parse 失敗・依存欠落・schema 不一致は exit 2(block)
#   - .env 読み取り遮断は path-aware(nested `config/.env` も対象)
#   - `git commit --amend` は option 順序に依存せず deterministic に拒否する
#     (permission の string-prefix ask では順序 variant を網羅できないため。通常 commit は対象外)
# exit 2 = block(stderr が理由)。それ以外の非ゼロも Claude Code は non-blocking error として
# 扱うため、block 意図の失敗はすべて明示的に exit 2 へ変換する。
set -euo pipefail

block() {
    echo "Blocked: $*" >&2
    exit 2
}

# 依存欠落は fail-closed(検査できないコマンドを通さない)
command -v jq >/dev/null 2>&1 || block "pre-bash-validate-hook requires jq but it is not installed (fail-closed)"

INPUT=$(cat) || block "failed to read hook input (fail-closed)"

# JSON object であり、tool_input.command が非空文字列であることを厳格検証する。
# matcher=Bash で起動される本 hook にとって、command を取り出せない入力は schema 違反 = block。
if ! echo "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    block "hook input is not valid JSON (fail-closed)"
fi
if ! COMMAND=$(echo "$INPUT" | jq -er '.tool_input.command | select(type == "string" and length > 0)' 2>/dev/null); then
    block "hook input has no non-empty tool_input.command (fail-closed)"
fi

# Block writes to block devices
if echo "$COMMAND" | grep -qE '(>|of=)\s*/dev/sd'; then
    block "write to block device detected in command"
fi

# Block mkfs on block devices
if echo "$COMMAND" | grep -qE 'mkfs\S*\s+/dev/sd'; then
    block "mkfs on block device detected"
fi

# git commit --amend を option 順序非依存で拒否する(H-011)。
# `git -c k=v -C path ... commit ... --amend ...` の形も対象。history rewrite は
# 明示のユーザー操作で行う(hook は ask を出せないため deny が fail-closed 側)。
if echo "$COMMAND" | grep -qE '(^|[;&|]|\s)git(\s+-[cC]\s*\S+|\s+--[A-Za-z-]+(=\S+)?)*\s+commit(\s|$)'; then
    if echo "$COMMAND" | grep -qE '(^|\s)--amend(\s|$|=)'; then
        block "git commit --amend is deny-by-policy (history rewrite)。必要な場合はユーザーが手動実行するか明示承認を得ること"
    fi
fi

# Block .env content reads while allowing existence checks.
# Defense-in-depth: permission rules は built-in tools と一部の直接 command にしか効かないため、
# ここで shell string を検査し、OS-level では sandbox の credentials/denyRead が最終境界になる。
# path-aware: 先頭・区切り文字・"/" の直後の .env を対象にする(nested `config/.env` を含む — H-014)
if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9._-])\.env([.-][A-Za-z0-9_.-]+)?([^A-Za-z0-9._-]|$)'; then
    # Dangerous readers: anything that emits file contents or sources them
    if echo "$COMMAND" | grep -qE '\b(cat|tac|rev|nl|pr|fold|fmt|head|tail|less|more|view|vi|vim|nano|emacs|ed|open|awk|gawk|sed|cut|sort|uniq|tr|column|paste|join|comm|od|xxd|hexdump|strings|base64|base32|grep|egrep|fgrep|zgrep|rg|ag|ack|python|python3|uv|node|bun|deno|ruby|perl|php|bash|sh|zsh|source|\.|tee|dd|cp|mv|install|rsync|scp|gzip|gunzip|zcat|bzcat|xzcat|tar|jar|unzip|diff|cmp|vimdiff|colordiff|wc|readlink|file)\b'; then
        block "command appears to read .env content. For existence check, use Glob, ls, stat, or test."
    fi
    # Redirection reading from .env: `cmd < .env`, `while read < config/.env`
    if echo "$COMMAND" | grep -qE '<\s*[^ ;|&]*\.env([.-][A-Za-z0-9_.-]+)?(\s|$)'; then
        block "input redirection from .env detected"
    fi
    # Command substitution or process substitution targeting .env
    if echo "$COMMAND" | grep -qE '(\$\(|<\(|`)[^)]*\.env'; then
        block "command/process substitution targeting .env detected"
    fi
fi

exit 0
