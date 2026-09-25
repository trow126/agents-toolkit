# Runbook: governance の一括変更（Phase 7）を live に適用する

`modernize/phase-7` の managed policy、hook、settings の変更を live に入れる手順。owner が行う（sudo と EX の再承認が必要）。

## 前提

- phase-4、phase-6 が integration で検証済み（付録 C.4、C.5、K3）で、この順に live に取り込めること。
- Phase 5 の決定（D1、D9）が出ていること。D9 の effort は repo ではなく live の `modelSettings` に owner が設定する。
- `docs/reports/accepted-exceptions.md` の EX-003 と EX-004 に、この変更の再承認記録と `claude/managed-settings.json` の hash があり、`scripts/validate-layout.sh` が PASS すること。

## 手順

1. Claude Code と Codex の session をすべて終了する。
2. live の `~/.claude/settings.json` に security のキーが無いことを確かめる（`install-managed-policy.sh` が検査する）。
3. 新しい managed を先に入れる。旧 managed は削除済みの hook（session-init、post-compact、prompt-submit）を登録しているので、取り込みを先にすると、次の session でその hook が失敗する。

   ```bash
   sudo ./scripts/install-managed-policy.sh --apply
   ```

4. live checkout に branch を fast-forward で取り込む（`git -C ~/agents-toolkit merge --ff-only modernize/phase-7`）。
5. `~/.claude/settings.json` は通常ファイルのまま残す（manifest から外れたので bootstrap は触らない）。
6. 確認する。

   ```bash
   ./scripts/install-managed-policy.sh --check
   ./bootstrap.sh --check
   ./scripts/discover-runtime.sh
   ```

   - `bootstrap.sh --check` の DRIFT が0件
   - discovery に FAIL が無く、`alias ... (env pin)` と `autoMemoryEnabled is false (from managed; EX-004)` が出る
   - 新しい session で `/context` に toolkit の hook の注入が無い

## rollback

1. `git -C ~/agents-toolkit reset --hard <適用前の commit>` で live checkout を戻す（owner が行う）。
2. 旧 commit の managed を入れ直す: `sudo ./scripts/install-managed-policy.sh --apply`。
3. 旧構成は `~/.claude/settings.json` を repo への symlink にしていた。通常ファイルのまま運用してよい（D5）。
