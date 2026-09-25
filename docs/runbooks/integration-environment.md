# Runbook: integration 環境

モデルを呼ぶ試験（`claude -p`、`codex exec`、委任、eval）、候補版の managed policy、hook の検証は、使い捨ての integration 環境だけで行う（近代化改修の指示書 §4.3）。作成、認証、破棄は owner が行う。

## 1. 作る

1. Windows 側で、使い捨ての WSL distro を import する（既存の distro は使わない。HOME を差し替えて隔離しない）。

   ```powershell
   wsl --import agents-toolkit-it C:\wsl\agents-toolkit-it <base-rootfs.tar>
   ```

2. 候補の branch を `git bundle` で渡し、distro の中に clone する。clone 先は、上位ディレクトリに AGENTS.md も CLAUDE.md も無い path にする。

   ```bash
   git -C ~/agents-toolkit bundle create /mnt/c/wsl/candidate.bundle modernize/phase-4
   ```

3. distro の中では `CLAUDE_CONFIG_DIR` と `CODEX_HOME` を設定しない（distro 自体が隔離の境界）。
4. 候補版の managed を導入してから配布する。

   ```bash
   sudo ./scripts/install-managed-policy.sh --apply
   ```

   ```bash
   AGENTS_TOOLKIT_REPO="$PWD" ./bootstrap.sh --apply
   ```

5. Windows host の `C:\Program Files\ClaudeCode\managed-settings.json` と `managed-settings.d` が空であることを確かめ、記録する。
6. Claude Code と Codex に owner がログインする。
7. `export AGENTS_TOOLKIT_SLACK_NOTIFY=off` を設定する。
8. `codex -p toolkit-implementer` の `/hooks` で、inline hook を review して trust する（K11）。Codex は trust を profile の config（repo への symlink）に書くので、続けて `./scripts/codex-profile-trust.py` で `~/.codex/config.toml` に移し、profile を HEAD に戻す。live でも同じ手順を踏む。

## 2. 費用の上限（D12）

- 1回あたり 2 USD。Claude は `--max-budget-usd 2` を付ける。
- 合計は Phase 4 で 15 USD、Phase 5 で 60 USD まで。
- `codex exec` には USD の上限が無いので、実行回数と題材の大きさで管理し、実行ごとに token 数を記録する。

## 3. Phase 4 で行う検証

- 委任を1件行う: 契約 → `codex-delegate` → 完了通知が main session に戻る → `verify-delegation` が evidence を出す → `/code-review`
- `stopped` を返す fixture（scope の外の変更が必要な題材）
- 付録 C.1 の Case 11〜13（repo の外での user-level 契約、instructionFiles と discovery の一致、toolkit の clone の中での `claudeMdExcludes`）
- K3（managed の deny `Agent(codex:codex-rescue)`）、K4、K6（`claude -p "/context"` を num_turns=0 で実行）、K7（委任の成否の記録）、K8（任意）、K11（inline hook が発火して block する）、K17（companion に profile 相当の設定を渡せるか。D8 の再評価）
- `scripts/audit-context-runtime.sh` と `scripts/discover-runtime.sh --online`

## 4. Phase 6 で行う検証（D7）

- `~/.codex/toolkit-divergent.config.toml` の link が bootstrap で作られていることを確かめる。
- `/break-consensus --cross` を1回実行する（D12 の1回 2 USD の範囲。Codex worker の token 数も記録する）。
- 付録 C.5 を確かめる。
  - brief の hash が両方の worker の出力で一致する（`break-consensus-cross collect`）。
  - 片方の出力がもう片方の入力に含まれない。Codex の入力は `run.json` の `codex.prompt_sha256` で、Claude worker の入力は workflow の journal（`<transcriptDir>/journal.jsonl`）の prompt で、どちらも `worker-prompt.md` と一致することを確かめる。
  - 実行の前後で `git status` が変わらない（`collect` と `finish`）。
  - Codex は read-only で動き、cwd は空の一時ディレクトリである（rollout の `turn_context`）。
  - Claude worker は Bash、Edit、Write、NotebookEdit を使えない（K18 の実行時の確認）。Workflow の `agent()` に同じ `disallowedTools` を付けて、Bash で `true` を実行するよう指示し、tool が無いことを transcript で確かめる。使えてしまう場合は、`cross.md` の fallback（Explore）に切り替える。
  - `result.md` に一致点、相違点、両方の生の出力がある。
  - 実装へ自動で移らない。
- `scripts/audit-context-runtime.sh` で、divergent profile の検査が PASS する。

## 5. skill の起動精度（K8）

skill の description、Claude Code の version、live の `skillOverrides` が変わったときに行う。managed も bootstrap も要らない。live の `~/.claude/settings.json` を `--settings` に渡して、モデルに一覧される skill を live と揃える。

```bash
./scripts/build-skill-trigger-eval.py /tmp/skill-trigger/atk --settings <live の settings.json の copy>
cd /tmp/skill-trigger && claude plugin eval ./atk --runs 3 -j 2 --model opus --ablation none --no-publish --max-cost-usd 4 --trust-plugin --json result.json
```

- `--no-publish` を必ず付ける（既定では HTML の報告を claude.ai に公開する）。
- 費用は12件を3回ずつで約 2.5 USD（2026-09-26）。上限は D12 に従い、owner が決める。
- 結果は `docs/reports/` に記録する（2026-09-26 の結果は `2026-09-26-k3-k8.md`）。

## 6. 破棄する

```powershell
wsl --unregister agents-toolkit-it
```

認証情報は distro と一緒に消える。結果は live 側の報告と commit message に残す。
