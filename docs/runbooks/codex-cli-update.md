# Runbook: Codex CLI の更新

Codex CLI の更新は owner が行う。更新すると catalog、既定の effort、prompt に注入される内容が変わることがあるので、次の順で進める。

## 1. 更新の前に

1. 実行中の Codex の委任（`/gh-codex-drive`、`/gh-roadmap-drive`）が無いことを確かめる。
2. codex-plugin-cc の broker と、その子の `codex app-server` を、孤児を含めてすべて停止する。更新前の binary のまま残った broker は、次の委任で旧版の Codex を動かしてしまう。

   ```bash
   ps -eo pid,ppid,lstart,args | grep -E "app-server-broker|codex app-server|codex-code-mode-host" | grep -v grep
   ```

   - `app-server-broker.mjs` とその子の `codex app-server` / `codex-code-mode-host` を `kill` で止める。
   - `--managed-daemon` の行は Codex 本体の daemon なので止めない。
3. 現状の snapshot を取る。

   ```bash
   ~/agents-toolkit/scripts/discover-runtime.sh
   ```

## 2. 更新する

普段の方法（npm など）で更新する。

## 3. 更新の後に

1. discovery を実行する。前回の snapshot と比べて、version、catalog、`config.toml` の既定の変化が WARN として出る。

   ```bash
   ~/agents-toolkit/scripts/discover-runtime.sh
   ```

2. 一時 HOME で prompt に注入される内容を確かめる（モデルは呼ばない）。`bootstrap.sh --apply` で一時 HOME に toolkit を配布してから、`codex debug prompt-input` を実行する。
   - toolkit の skill が一覧に出ていること、manual-only の skill が出ていないこと
   - core-contract が1回だけ入っていること
   - `codex debug models` の bundled catalog の変化
3. FAIL が出たら、routing 表の該当行を昇格ゲート（discovery → effort sweep → replay eval → routing 表の commit）で見直す。一時的に fallback に切り替えたときは、routing 表の evidence にその理由を書く。
4. 結果と Level の判定（指示書 §12）を Issue か commit message に記録する。

## 参照

- 2026-09-25 の基準値: [`docs/reports/2026-09-25-codex-0.157.0-state.md`](../reports/2026-09-25-codex-0.157.0-state.md)
- 公式: `github.com/openai/codex` の releases、`learn.chatgpt.com/docs`
