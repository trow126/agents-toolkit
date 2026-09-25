# Phase 4 の integration 検証（2026-09-25）

近代化 Phase 4（委任、D8）と、Phase 7 の managed を合わせた候補（`modernize/phase-7` の `2e3f457`。phase-4 と phase-6 を含む）を、integration 環境で検証した結果。

## 環境

- host `mini`（Ubuntu 26.04、Tailscale 経由の SSH）。使い捨ての distro の代わりに、owner の選択で mini 本体を使った（2026-09-25）。
- Claude Code 2.1.282、Codex CLI 0.157.0。owner がログイン済み。
- 候補の managed を `/etc/claude-code/managed-settings.d/20-agents-toolkit-security.json` に sudo で導入し（hash `39a249092535…`）、`bootstrap.sh --apply` で配布した。`bootstrap.sh --check` の DRIFT は0件。
- live と揃えた項目: `~/.claude/settings.json`（live の写しに `AGENTS_TOOLKIT_SLACK_NOTIFY=off` を加えた）、Codex の既定値と `[agents]`、plugin（superpowers 6.4.1 は無効、codex-plugin-cc 1.0.6 `db52e28`）。
- 元の設定は `~/.local/state/agents-toolkit-it-backup/20260925/` に退避した（認証ファイルは含めない）。

## 結果

| 項目 | 結果 | 根拠 |
|---|---|---|
| 委任1件（通し） | PASS | `claude --bg`（fable/high）で、契約 → background の `codex-delegate` → 完了通知 → `verify-delegation` が GATE PASS（2ファイル、11行、check 1/1）→ diff の review。evidence は `passed: true` |
| `stopped` の fixture | PASS | scope の外が必要な契約で、Codex は変更0件で `stopped`（`out_of_scope_path`）を返し、gate は FAIL と判定して evidence を残した |
| Case 11 | PASS | repo の外で、Memory files は `~/.claude/CLAUDE.md` と import された core-contract の各1回 |
| Case 12 | PASS | debug log に、`pluginConfigs["agents-md@builtin"].options` がどこにも無く既定値、と出る。discovery の判定（`claude-md-or-agents-md`、既定）と一致 |
| Case 13 / K16 の後半 | PASS | toolkit の clone の中でも、`~/.claude/CLAUDE.md` と core-contract が各1回。`claudeMdExcludes` は symlink の `~/.claude/CLAUDE.md` を除外しない |
| K3 | 一部 | managed の deny で、Agent tool のモデル向けの説明から `codex:codex-rescue` が消える（init の登録一覧には残る）。明示的に呼ぶと、permission より先に PreToolUse の guard が止めるので、呼び出し時の deny 単独の効果は切り分けていない |
| K4 | Case 9 と 13 で代替 | 起動時の重複は無い。nested の読込は Case 9（authoring 環境）で除外を確認済み |
| K6 | PASS | `claude -p "/context"` が num_turns=0、cost=0 で Memory files を返す |
| K7 | PASS | 委任ごとの evidence が git-dir に残る |
| K8 | 使える | `claude plugin eval` がある（実行はしていない） |
| K11 | PASS（trust が必要） | inline hook は `codex exec` の中で発火し、exit 2 で違反を返し、Codex が修正した。trust は `~/.codex/config.toml` に置いても効く |
| K17 | companion では不可 | app-server の `ThreadStartParams` には `config` と `developerInstructions` があるが、companion 1.0.6 は cwd、model、approvalPolicy、sandbox しか渡さない。D8（`codex exec` の launcher）を維持する |
| audit | PASS（下の修正後） | C.2 の profile の検査を含む |
| discovery | FAIL 0 | alias の4つは env pin で解決、`autoMemoryEnabled` は managed から false |

## 費用（D12: Phase 4 は 15 USD まで）

- Claude: K3（haiku）0.028 USD、`claude -p` の委任 0.575 USD（完了せず。下の所見 5）、`--bg` の委任 約 1.08 USD（transcript の token からの推定）。計 約 1.7 USD。
- Codex: 5回。K11 の2回（low。入力 111,560 / 76,443、出力 708 / 522）、`stopped`（medium。入力 46,542、出力 711）、通しの委任（medium。入力 64,843、出力 715）、`claude -p` で中断された1回（usage なし）。

## 所見と修正（`modernize/phase-7` の追加 commit）

1. guard が `codex:codex-rescue` を拒否するときの案内が、companion の task を指していた。`codex-delegate` を案内するように直した。
2. audit が Codex の superpowers を「導入済みで無効」と要求していたが、Codex 0.157.0 には superpowers が無い（marketplace は `openai-curated-remote` に移った）。live でも FAIL していた。「無いか無効なら合格、有効なら不合格」に直した。
3. Codex の TUI で hook を trust すると、trust、project の trust、UI の状態が、symlink を通って repo の profile に書き込まれる。`scripts/codex-profile-trust.py` を加え、`~/.codex/config.toml` に移して profile を HEAD に戻す。validator は、profile に残った Codex の状態を拒否する。
4. launcher が途中で止まると `active.json` が残り、次の委任が「別の委任が active」と拒否される。`active.json` に launcher の pid と終了を記録し、途中で止まった委任を stale と明示するようにした。
5. `claude -p` では、ターンの終わりに session が終わり、background の Codex も止まる。委任は対話か `claude --bg` の session で行うと、gh-codex-drive に明記した。

## 残り

- Phase 6 の C.5（`/break-consensus --cross`）と K18 の実行時の確認。
- 委任の review での `/code-review` の実行（今回は `git diff` の review で代替した）。
- mini の後片付け（managed の削除、退避した設定の復元、`~/.profile` の Slack 行の削除）。
