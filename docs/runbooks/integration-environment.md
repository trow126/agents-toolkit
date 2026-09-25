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
8. `codex` の `/hooks` などで、profile `toolkit-implementer` の inline hook を review して trust する（K11）。

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

## 4. 破棄する

```powershell
wsl --unregister agents-toolkit-it
```

認証情報は distro と一緒に消える。結果は live 側の報告と commit message に残す。
