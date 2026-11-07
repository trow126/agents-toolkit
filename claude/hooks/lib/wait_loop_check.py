"""wait-loop-check: refuse a wait loop whose inline `python -c` body cannot even compile.

A failing probe inside `while` / `until` does not end the loop, and `2>/dev/null` or `|| echo x`
makes the failure look like "not done yet", so no completion notice ever arrives. In 2026-11
(edge-agent) an f-string syntax error hid a finished job for about an hour. A shell syntax error in
the whole command needs no check: the shell exits at once and the failure notice arrives.

Reads the command on stdin (the hook has already removed heredoc bodies that are not fed to a
shell). Exit 0 = allow, 2 = syntax error (the reason goes to stdout). Bodies are only compiled,
never run. Bodies that cannot be read statically are skipped: shell expansion, unterminated quotes,
and code nested inside another quoted command such as `ssh host 'python3 -c ...'`.
"""

import re
import sys
import warnings

LOOP_WORD = re.compile(r"(?:while|until)(?=[\s;&|()]|$)")
PYTHON_C = re.compile(
    r"(?:[^\s;&|()'\"`]*/)?python(?:\d+(?:\.\d+)*)?"
    r"(?:\s+-[XW]\s+\S+|\s+-[A-Za-z]+)*?\s+-[A-Za-z]*c\s+"
)
WORD_START_AFTER = " \t\n;&|(`"
WORD_END = " \t\n;&|()<>"
DOUBLE_QUOTE_ESCAPABLE = '"\\$`'


def read_word(cmd: str, start: int) -> tuple[str | None, int]:
    """Read one shell word.

    Args:
        cmd: The whole command.
        start: Index of the word's first character.

    Returns:
        The word with quotes removed and the index after it. The word is None when it has shell
        expansion or an unterminated quote, because its value is then unknown.
    """
    out: list[str] = []
    literal = True
    i = start
    while i < len(cmd) and cmd[i] not in WORD_END:
        c = cmd[i]
        if c == "'":
            end = cmd.find("'", i + 1)
            if end < 0:
                return None, len(cmd)
            out.append(cmd[i + 1 : end])
            i = end + 1
        elif c == '"':
            i += 1
            while True:
                if i >= len(cmd):
                    return None, len(cmd)
                c = cmd[i]
                if c == '"':
                    i += 1
                    break
                if c == "\\" and i + 1 < len(cmd):
                    escaped = cmd[i + 1]
                    if escaped in DOUBLE_QUOTE_ESCAPABLE:
                        out.append(escaped)
                    elif escaped != "\n":
                        out.append(c + escaped)
                    i += 2
                    continue
                if c in "$`":
                    literal = False
                out.append(c)
                i += 1
        elif c == "\\":
            out.append(cmd[i + 1 : i + 2])
            i += 2
        else:
            if c in "$`":
                literal = False
            out.append(c)
            i += 1
    return ("".join(out) if literal else None), i


def scan(cmd: str) -> tuple[bool, list[str]]:
    """Find whether the command has a loop keyword, and its statically readable `python -c` bodies.

    Quoted text is skipped, except that `$(` inside double quotes starts a new command context.

    Args:
        cmd: The command, with non-shell heredoc bodies removed.

    Returns:
        Whether a standalone `while` / `until` word exists, and the bodies.
    """
    has_loop = False
    bodies: list[str] = []
    stack = ["normal"]
    i = 0
    while i < len(cmd):
        c = cmd[i]
        if stack[-1] == "double":
            if c == "\\":
                i += 2
            elif c == '"':
                stack.pop()
                i += 1
            elif cmd.startswith("$(", i):
                stack.append("normal")
                i += 2
            else:
                i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c == "'":
            end = cmd.find("'", i + 1)
            if end < 0:
                break
            i = end + 1
            continue
        if c == '"':
            stack.append("double")
            i += 1
            continue
        if c == "(":
            stack.append("normal")
        elif c == ")" and len(stack) > 1:
            stack.pop()
        if i == 0 or cmd[i - 1] in WORD_START_AFTER:
            if c == "#":
                newline = cmd.find("\n", i)
                if newline < 0:
                    break
                i = newline
                continue
            if LOOP_WORD.match(cmd, i):
                has_loop = True
            python_c = PYTHON_C.match(cmd, i)
            if python_c:
                body, i = read_word(cmd, python_c.end())
                if body is not None:
                    bodies.append(body)
                continue
        i += 1
    return has_loop, bodies


def syntax_error(body: str) -> str | None:
    """Compile a body without running it.

    Args:
        body: Python source.

    Returns:
        A description of the error, or None when the body compiles.
    """
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            compile(body, "<python -c>", "exec", dont_inherit=True)
    except SyntaxError as err:
        line = (err.text or "").strip()
        return f"{type(err).__name__}: {err.msg} (line {err.lineno}: {line})"
    except ValueError as err:
        return f"SyntaxError: {err}"
    return None


def main() -> int:
    cmd = sys.stdin.buffer.read().decode("utf-8", "replace")
    has_loop, bodies = scan(cmd)
    if not has_loop:
        return 0
    for body in bodies:
        error = syntax_error(body)
        if error:
            print(
                f"待機ループ内の python -c に構文エラーがある（{error}）。"
                "ループ内の失敗ではループが終わらず、2>/dev/null や || echo で隠れると完了を検知できない。"
                "本文を直し、判定コマンドを1回だけ単独で実行して期待どおりの値が出ることを確かめてからループに入れること。"
                "複雑な判定はスクリプトファイルに分ける"
            )
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
