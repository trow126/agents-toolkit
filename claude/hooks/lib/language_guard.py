"""language-guard: keep replies to the user in the configured response language (Japanese).

Two managed hook events, one rule: when ~/.claude/settings.json sets "language" to Japanese,
- Stop: block the stop once when the final reply (last_assistant_message) is written in English:
  at least MIN_LATIN Latin letters and a Japanese share below MAX_SHARE, counted after removing
  code blocks, inline code, URLs, and paths. stop_hook_active=true lets the stop through, so a
  turn is blocked at most once.
- PreToolUse AskUserQuestion: refuse a question whose text has no Japanese character.

Exit 0 = allow, 2 = block (stderr goes to Claude), 1 = internal error (non-blocking: the guard is
an optional quality check and must never trap a session). In 2026-10/11 transcripts, 21 of 22
"日本語でお願い" corrections followed a reply with a Japanese share near 0; the thresholds flagged 40 of
1,015 turn-final replies, all of them English.
"""
import json
import os
import re
import sys
from pathlib import Path

MIN_LATIN = 80
MAX_SHARE = 0.1
JAPANESE_VALUES = {"japanese", "日本語", "ja", "ja-jp"}
JA = re.compile(r"[぀-ヿ一-鿿]")
LATIN = re.compile(r"[A-Za-z]")


def configured_japanese() -> bool:
    path = Path(os.environ.get("HOME", "~")).expanduser() / ".claude/settings.json"
    if not path.is_file():
        return False
    value = json.loads(path.read_text(encoding="utf-8")).get("language")
    return isinstance(value, str) and value.strip().lower() in JAPANESE_VALUES


def prose(text: str) -> str:
    text = re.sub(r"```.*?```|~~~.*?~~~", " ", text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", " ", text)
    return re.sub(r"https?://\S+|\S*/\S+", " ", text)


def japanese_share(text: str) -> tuple[int, float]:
    body = prose(text)
    ja, latin = len(JA.findall(body)), len(LATIN.findall(body))
    return latin, (ja / (ja + latin) if ja + latin else 1.0)


def check_stop(event: dict) -> int:
    if event.get("stop_hook_active") is True:
        return 0
    text = event.get("last_assistant_message")
    if not isinstance(text, str) or not text.strip():
        return 0  # older runtimes do not send the final reply; nothing to check
    latin, share = japanese_share(text)
    if latin >= MIN_LATIN and share < MAX_SHARE:
        print(f"language-guard: 直前の返答は英語で書かれている（コード・パスを除いた本文の日本語の割合 {share:.0%}）。"
              "settings.json の language は japanese なので、同じ内容を自然な日本語で書き直して返すこと。"
              "英語のまま残すのはコード名・コマンド・ファイル名・固有名詞だけにする。", file=sys.stderr)
        return 2
    return 0


def check_ask(event: dict) -> int:
    questions = (event.get("tool_input") or {}).get("questions")
    if not isinstance(questions, list):
        return 0
    english = [q.get("question", "") for q in questions
               if isinstance(q, dict) and not JA.search(str(q.get("question", "")))]
    if english:
        print("language-guard: AskUserQuestion の質問文に日本語が含まれていない（"
              + " / ".join(s[:60] for s in english) + "）。settings.json の language は japanese なので、"
              "質問文・選択肢・説明を日本語で書き直して呼び直すこと。", file=sys.stderr)
        return 2
    return 0


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if not isinstance(event, dict) or not configured_japanese():
            return 0
        name = event.get("hook_event_name")
        if name == "Stop":
            return check_stop(event)
        if name == "PreToolUse" and event.get("tool_name") == "AskUserQuestion":
            return check_ask(event)
        return 0
    except Exception as exc:  # noqa: BLE001 - report and let the action through (optional check)
        print(f"language-guard: internal error, not checked: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
