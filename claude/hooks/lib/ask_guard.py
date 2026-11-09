"""ask-guard: ask the user through AskUserQuestion instead of ending a reply with a prose question.

Managed Stop hook. In an interactive session (CLAUDE_CODE_ENTRYPOINT is cli or claude-desktop), block
the stop once when the final reply (last_assistant_message) asks the user something in prose: a
sentence in its last LAST_PARAGRAPHS paragraphs ends with ? / ？ or with ますか・ですか・でしょうか・
ませんか・ましょうか, counted after removing code blocks, inline code, URLs, and quoted lines. The block
tells Claude to put the same question to the user with AskUserQuestion. stop_hook_active=true lets
the stop through, so a turn is blocked at most once and a false positive costs one extra stop.
Headless runs (sdk-cli) and runtimes that do not set the entrypoint are not checked: there is no one
to answer AskUserQuestion there.

Exit 0 = allow, 2 = block (stderr goes to Claude), 1 = internal error (non-blocking: the guard is
an optional quality check and must never trap a session). In 2026-10/11 transcripts the owner
asked for "アスクモードで" in 18 sessions; 106 of 817 turn-final replies ended with such a prose
question, and every one sampled asked for a decision or an approval.
"""
import json
import os
import re
import sys

LAST_PARAGRAPHS = 2
INTERACTIVE_ENTRYPOINTS = {"cli", "claude-desktop"}
QUESTION = re.compile(
    r"(?:[?？]|(?:ます|です|でしょう|ません|ましょう)か[。．]?)(?=[\s*_)）]*(?:$|\s))", re.M)


def paragraphs(text: str) -> list[str]:
    text = re.sub(r"```.*?```|~~~.*?~~~", "\n\n", text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"(?m)^\s*>.*$", " ", text)
    return [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]


def prose_question(text: str) -> str | None:
    for para in paragraphs(text)[-LAST_PARAGRAPHS:]:
        for line in para.splitlines():
            if QUESTION.search(line):
                return line.strip()
    return None


def check_stop(event: dict) -> int:
    if event.get("stop_hook_active") is True:
        return 0
    text = event.get("last_assistant_message")
    if not isinstance(text, str) or not text.strip():
        return 0  # older runtimes do not send the final reply; nothing to check
    question = prose_question(text)
    if question is None:
        return 0
    print(f"ask-guard: 直前の返答は文章の質問で終わっている（「{question[:80]}」）。"
          "ユーザーへの確認・承認・選択は AskUserQuestion で聞くこと。返答本文はもう表示されているので"
          "繰り返さず、同じ確認を選択肢付きの AskUserQuestion で呼び直す。"
          "ユーザーへの質問でなければ（修辞疑問や引用など）、そのまま止まってよい。", file=sys.stderr)
    return 2


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if not isinstance(event, dict) or event.get("hook_event_name") != "Stop":
            return 0
        if os.environ.get("CLAUDE_CODE_ENTRYPOINT") not in INTERACTIVE_ENTRYPOINTS:
            return 0
        return check_stop(event)
    except Exception as exc:  # noqa: BLE001 - report and let the stop through (optional check)
        print(f"ask-guard: internal error, not checked: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
