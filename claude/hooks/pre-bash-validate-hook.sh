#!/bin/bash
# PreToolUse hook: validate Bash commands before execution
# Blocks dangerous patterns by exiting with code 2 + stderr message
# Only checks tool_input.command from Claude's Bash tool calls

set -uo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Block writes to block devices
if echo "$COMMAND" | grep -qE '(>|of=)\s*/dev/sd'; then
    echo "Blocked: write to block device detected in command" >&2
    exit 2
fi

# Block mkfs on block devices
if echo "$COMMAND" | grep -qE 'mkfs\S*\s+/dev/sd'; then
    echo "Blocked: mkfs on block device detected" >&2
    exit 2
fi

# Block .env content reads while allowing existence checks.
# Defense-in-depth against sandbox-disabled mode; permission patterns alone
# cannot catch head/tail/grep/python/redirections etc.
if echo "$COMMAND" | grep -qE '(^|[^A-Za-z0-9._/-])\.env([.-][A-Za-z0-9_.-]+)?([^A-Za-z0-9._-]|$)'; then
    # Dangerous readers: anything that emits file contents or sources them
    if echo "$COMMAND" | grep -qE '\b(cat|tac|rev|nl|pr|fold|fmt|head|tail|less|more|view|vi|vim|nano|emacs|ed|open|awk|gawk|sed|cut|sort|uniq|tr|column|paste|join|comm|od|xxd|hexdump|strings|base64|base32|grep|egrep|fgrep|zgrep|rg|ag|ack|python|python3|uv|node|bun|deno|ruby|perl|php|bash|sh|zsh|source|\.|tee|dd|cp|mv|install|rsync|scp|gzip|gunzip|zcat|bzcat|xzcat|tar|jar|unzip|diff|cmp|vimdiff|colordiff)\b'; then
        echo "Blocked: command appears to read .env content. For existence check, use Glob, ls, stat, test, or file." >&2
        exit 2
    fi
    # Redirection reading from .env: `cmd < .env`, `while read < .env`
    if echo "$COMMAND" | grep -qE '<\s*[^ ;|&]*\.env([.-][A-Za-z0-9_.-]+)?(\s|$)'; then
        echo "Blocked: input redirection from .env detected" >&2
        exit 2
    fi
    # Command substitution or process substitution targeting .env
    if echo "$COMMAND" | grep -qE '(\$\(|<\(|`)[^)]*\.env'; then
        echo "Blocked: command/process substitution targeting .env detected" >&2
        exit 2
    fi
fi

exit 0
