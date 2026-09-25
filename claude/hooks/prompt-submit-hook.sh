#!/usr/bin/env bash
# UserPromptSubmit hook: https://code.claude.com/docs/en/hooks
# owner 決定 D3②（docs/reports/owner-decisions.md）により、毎 prompt の reminder 注入を
# 停止した。同じ内容は core-contract と claude/CLAUDE.md の「Ownerとrouting」にある。
# managed policy から登録を外すまでは呼ばれ続けるため、stdin を読み捨てて何も出力せず
# exit 0 する。gate ではないので、どの入力でも prompt を block しない。

MAX_INJECTION_BYTES=0

cat >/dev/null 2>/dev/null || true
exit 0
