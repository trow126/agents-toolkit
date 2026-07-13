#!/usr/bin/env bash
# ask-claude.sh: Invoke Claude Code Fable as an independent second-opinion oracle.
# Progress is written to stderr; stdout contains only the final Claude answer.
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: ask-claude.sh --cwd <dir> [--timeout <sec>] [--allow-web] [--include-cwd] < prompt
  --cwd <dir>       Reference directory (required, must not resolve to $HOME).
  --timeout <sec>   Positive wall-clock cap in seconds (default 1200).
  --allow-web       Allow only Claude's WebSearch and WebFetch tools.
  --include-cwd     Allow read-only Read/Glob/Grep access to <cwd> via --add-dir.
                    Do NOT use in dirs containing .env / credentials / secrets.
EOF
}

usage_error() {
  echo "[ask-claude] $1" >&2
  usage >&2
  exit 64
}

cwd=""
timeout_sec=1200
allow_web=0
include_cwd=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd)
      [[ $# -ge 2 ]] || usage_error "--cwd value required"
      cwd="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || usage_error "--timeout value required"
      timeout_sec="$2"
      shift 2
      ;;
    --allow-web)
      allow_web=1
      shift
      ;;
    --include-cwd)
      include_cwd=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

for cmd in claudecode timeout realpath jq mktemp cat grep rm; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "[ask-claude] missing dependency: $cmd" >&2
    exit 127
  }
done

[[ "$timeout_sec" =~ ^[1-9][0-9]*$ ]] || usage_error "--timeout must be a positive integer"
[[ -n "$cwd" && -d "$cwd" ]] || {
  echo "[ask-claude] --cwd must be an existing directory" >&2
  exit 2
}
if ! resolved_cwd="$(realpath -- "$cwd")"; then
  echo "[ask-claude] failed to resolve --cwd" >&2
  exit 2
fi
if ! resolved_home="$(realpath -- "$HOME")"; then
  echo "[ask-claude] failed to resolve HOME" >&2
  exit 2
fi
[[ "$resolved_cwd" != "$resolved_home" ]] || {
  echo "[ask-claude] --cwd must not resolve to \$HOME" >&2
  exit 2
}

umask 077
run_dir="$(mktemp -d)"
prompt_file="$run_dir/prompt"
result_file="$run_dir/result"
cleanup() {
  rm -rf -- "$run_dir"
}
trap cleanup EXIT HUP INT TERM

cat >"$prompt_file"
if [[ ! -s "$prompt_file" ]] || ! LC_ALL=C grep -q '[^[:space:]]' "$prompt_file"; then
  echo "[ask-claude] empty prompt on stdin" >&2
  exit 65
fi

declare -a claude_args=(
  -p
  --verbose
  --output-format stream-json
  --permission-mode dontAsk
  --safe-mode
  --no-session-persistence
  --prompt-suggestions false
  --model fable
  --effort high
)
declare -a allowed_tools=()
if (( include_cwd )); then
  allowed_tools+=(Read Glob Grep)
  claude_args+=(--add-dir "$resolved_cwd")
fi
if (( allow_web )); then
  allowed_tools+=(WebSearch WebFetch)
fi
if (( ${#allowed_tools[@]} == 0 )); then
  claude_args+=(--tools "")
else
  tools_csv="$(IFS=,; echo "${allowed_tools[*]}")"
  claude_args+=(--tools "$tools_csv" --allowedTools "$tools_csv")
fi

parse_stream() {
  local output_file="$1"
  local line event_type subtype is_error model tool_names
  local parse_failed=0
  local result_count=0

  while IFS= read -r line; do
    if [[ -z "$line" ]] || ! jq -e . >/dev/null 2>&1 <<<"$line"; then
      echo "[ask-claude] malformed stream-json event" >&2
      parse_failed=1
      continue
    fi

    event_type="$(jq -r '.type // empty' <<<"$line")"
    if [[ -z "$event_type" ]]; then
      echo "[ask-claude] stream-json event is missing type" >&2
      parse_failed=1
      continue
    fi

    case "$event_type" in
      system)
        subtype="$(jq -r '.subtype // empty' <<<"$line")"
        if [[ "$subtype" == "init" ]]; then
          model="$(jq -r '.model // "unknown"' <<<"$line")"
          tool_names="$(jq -r '(.tools // []) | join(",")' <<<"$line")"
          printf '[ask-claude] init model=%s tools=%s\n' "$model" "${tool_names:-none}" >&2
        elif [[ "$subtype" == "task_progress" ]]; then
          echo "[ask-claude] progress" >&2
        fi
        ;;
      assistant)
        tool_names="$(
          jq -r '[.message.content[]? | select(.type == "tool_use") | .name] | join(",")' <<<"$line"
        )"
        [[ -n "$tool_names" ]] && printf '[ask-claude] tools=%s\n' "$tool_names" >&2
        ;;
      result)
        result_count=$((result_count + 1))
        subtype="$(jq -r '.subtype // empty' <<<"$line")"
        is_error="$(jq -r 'if has("is_error") then .is_error else true end' <<<"$line")"
        if (( result_count != 1 )); then
          echo "[ask-claude] duplicate result event" >&2
          parse_failed=1
          continue
        fi
        if [[ "$subtype" != "success" || "$is_error" != "false" ]]; then
          echo "[ask-claude] Claude returned an error result" >&2
          parse_failed=1
          continue
        fi
        if ! jq -e '.result | type == "string" and test("\\S")' >/dev/null 2>&1 <<<"$line"; then
          echo "[ask-claude] Claude returned an empty result" >&2
          parse_failed=1
          continue
        fi
        jq -j '.result' <<<"$line" >"$output_file"
        echo "[ask-claude] result received" >&2
        ;;
    esac
  done

  if (( result_count == 0 )); then
    echo "[ask-claude] Claude stream ended without a result" >&2
    parse_failed=1
  fi
  (( parse_failed == 0 )) || return 70
}

printf '[ask-claude] starting Fable/high (timeout=%ss, web=%s, cwd=%s)\n' \
  "$timeout_sec" "$allow_web" "$include_cwd" >&2
cd -- "$run_dir"
set +e
CLAUDE_STREAM_IDLE_TIMEOUT_MS=900000 \
  timeout --kill-after=10s "$timeout_sec" claudecode "${claude_args[@]}" <"$prompt_file" \
  | parse_stream "$result_file"
pipeline_status=("${PIPESTATUS[@]}")
set -e

claude_status="${pipeline_status[0]}"
parser_status="${pipeline_status[1]}"
if (( claude_status == 124 )); then
  echo "[ask-claude] timed out after ${timeout_sec}s" >&2
  exit 124
fi
if (( claude_status != 0 )); then
  echo "[ask-claude] claudecode exited with status $claude_status" >&2
  exit "$claude_status"
fi
if (( parser_status != 0 )); then
  exit "$parser_status"
fi

cat "$result_file"
