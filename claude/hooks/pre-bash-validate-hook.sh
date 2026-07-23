#!/bin/bash
# PreToolUse hook: validate Bash commands before execution (fail-closed — 2026-07-24 H-011/H-014)
#
# 位置づけ(重要):
#   本 hook は raw command string に対する quote 正規化つき heuristic であり、
#   「事故と平易な迂回の防止層」である。shell 評価後の argv は解析しない(できない)ため、
#   security boundary としては扱わない。最終境界は次の決定論的レイヤが担う:
#     - filesystem: permission の Read/Edit deny が sandbox filesystem へ統合され
#       OS-level で child process にも適用される(`Read(//**/.env)` 等)
#     - 破壊的操作の外部反映: `git push` 等の content-scoped ask(sandbox auto-allow 中も prompt)
#     - shell 経由の再評価: `Bash(bash *)`/`Bash(sh *)` 等の deny、`git -c*` 等の ask
#
# 方針:
#   - fail-closed: 入力の parse 失敗・依存欠落・schema 不一致は exit 2(block)
#   - 検査は quote 除去後の文字列(NORM)に対して行う(`--am""end` の類を吸収)
#   - runtime 構築 path(base64 復号や変数連結で literal が現れないもの)は本 hook の対象外。
#     その場合も上記 OS/permission 境界が実アクセスを遮断する
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

# JSON object であり、tool_input.command が非空文字列であることを厳格検証する。
# matcher=Bash で起動される本 hook にとって、command を取り出せない入力は schema 違反 = block。
if ! echo "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    block "hook input is not valid JSON (fail-closed)"
fi
if ! COMMAND=$(echo "$INPUT" | jq -er '.tool_input.command | select(type == "string" and length > 0)' 2>/dev/null); then
    block "hook input has no non-empty tool_input.command (fail-closed)"
fi

# quote 正規化: `--am""end` / `'.e'nv` のような quote 分割 literal を復元する。
# \042 = double quote, \047 = single quote
NORM=$(printf '%s' "$COMMAND" | tr -d '\042\047')

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
# runtime 構築 path は permission の Read(//**/.env) deny → sandbox filesystem 統合が
# OS-level で遮断する(本 hook の対象外)。
# path-aware: 先頭・区切り文字・"/" の直後の .env を対象にする(nested `config/.env` を含む — H-014)
if printf '%s' "$NORM" | grep -qE '(^|[^A-Za-z0-9._-])\.env([.-][A-Za-z0-9_.-]+)?([^A-Za-z0-9._-]|$)'; then
    # Dangerous readers: anything that emits file contents or sources them
    if printf '%s' "$NORM" | grep -qE '\b(cat|tac|rev|nl|pr|fold|fmt|head|tail|less|more|view|vi|vim|nano|emacs|ed|open|awk|gawk|sed|cut|sort|uniq|tr|column|paste|join|comm|od|xxd|hexdump|strings|base64|base32|grep|egrep|fgrep|zgrep|rg|ag|ack|python|python3|uv|uvw|node|bun|deno|ruby|perl|php|bash|sh|zsh|source|\.|tee|dd|cp|mv|install|rsync|scp|gzip|gunzip|zcat|bzcat|xzcat|tar|jar|unzip|diff|cmp|vimdiff|colordiff|wc|readlink|file)\b'; then
        block "command appears to read .env content. For existence check, use Glob, ls, stat, or test."
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
