#!/usr/bin/env python3
"""Emit a bounded Claude Code hook JSON object from stdin.

The final UTF-8 output, including JSON syntax and newline, never exceeds
MAX_OUTPUT_BYTES. Input is normalized to a single line before truncation.
"""
from __future__ import annotations

import json
import sys

MAX_OUTPUT_BYTES = 512


def encode(message: str) -> bytes:
    return (
        json.dumps(
            {"systemMessage": message},
            ensure_ascii=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def main() -> int:
    text = " ".join(sys.stdin.read().split())
    if not text:
        text = "[Context unavailable]"

    payload = encode(text)
    if len(payload) > MAX_OUTPUT_BYTES:
        lo, hi = 0, len(text)
        suffix = "..."
        while lo < hi:
            mid = (lo + hi + 1) // 2
            candidate = text[:mid].rstrip() + suffix
            if len(encode(candidate)) <= MAX_OUTPUT_BYTES:
                lo = mid
            else:
                hi = mid - 1
        text = text[:lo].rstrip() + suffix
        payload = encode(text)

    if len(payload) > MAX_OUTPUT_BYTES:
        raise SystemExit("bounded systemMessage encoder invariant failed")
    sys.stdout.buffer.write(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
