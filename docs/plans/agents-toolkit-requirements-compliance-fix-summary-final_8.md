# agents-toolkit 要件適合性再レビュー修正サマリー — final_8（内部版 v9）

- 修正対象: `agents-toolkit-modernized-final_7.zip` / `modernization-report-final_7.md` / `agents-toolkit-modernization-final_7.patch`
- 修正 commit: `a3c75cd8f7750943385f2b67cd60b3445f15e15d`
- baseline: `7d193c2`
- static 判定: **COMPLETE**
- final 判定: **COMPLETE**

> **Post-acceptance owner override (2026-07-24):** この文書の COMPLETE / PASS は fail-closed policy に対する履歴である。その後 owner が「完全に以前どおり: bypassPermissions に戻す」と明示し、現行 policy は permission confirmation 省略・sandbox 無効となった。M-04/C-02 の prompt/sandbox 保護は EX-003 により supersede されている。

## 指摘対応

| ID | 対応 | 状態 |
|---|---|---|
| B-01 | 添付 PDF の実 SHA-256 `dc5fe5b333f0d0fda91fec72745ad458b3217e2be49a7b44c3093eb73287fdda` を source manifest に固定し、verifier を追加。成果物自身による owner approval の自己申告と循環的追認を削除。PDF に存在しない Stage 6–7 は非規範の実装マッピングとして明示 | Static closed |
| C-02 | security policy を user scope から OS-managed scope へ移動。managed-only lock、root-owned installer、project/local policy gate、ConfigChange/PreToolUse/runtime gate、negative fixtures を追加 | Static closed / managed composition・preflight・PreToolUse live verified |
| H-03 | `--accept-custom-xdg` と waiver continuation を廃止。標準 XDG path と realpath-equivalent のみ許可し、それ以外は fail-closed | Closed |
| H-04 | 137 行の one-element/one-row inventory と 11 軸監査を追加。review/progress/retrospective を active unique path 8 件として再定義し、SessionStart/PostCompact の typical/max bytes を計測 | Closed |
| M-04 | managed Bash allow を 0 件化し、`permissions.ask: ["Bash"]` と `autoAllowBashIfSandboxed: false` を採用。read-only Bash と全 `gh` operation を approval gate へ移動 | Closed / live prompt verified |
| M-05 | current-state 文書を v9 へ統一。XDG tests を ambient environment から隔離し、trailing slash/`..` を正規化 | Closed |
| 追加修正 | 公式 schema に合わせ `disableAutoMode` を top-level managed key へ移動し、nested placement を validator/test で拒否。明示 metric `auto_mode_lockout_ok` を追加 | Closed |

## 主要構成変更

- `claude/settings.json`: non-security user preference のみ。native auto memory と auto mode customization を削除
- `claude/managed-settings.json`: permissions、sandbox、credentials、hooks、bypass/auto-mode lockout、version floor
- `scripts/install-managed-policy.sh`: Linux/WSL2 または macOS の managed drop-in へ exact root-owned copy を導入
- `claude/bin/project-policy-gate`: project/local settings の permissions/hooks/sandbox/security env を拒否
- `docs/reports/inventory-elements.tsv`: 137 要素の機械検証可能な監査正本
- `codex/references/python-quality.md`: Python quality guidance を非 skill reference へ移し、新規 behavior skill を `break-consensus` 1件に限定

## Static validation 結果

- `scripts/validate-layout.sh`: PASS、WARN 0
- `shared/bin/sync-shared-rules.sh --check`: PASS
- `scripts/package-release.sh --check`: PASS
- requirements PDF hash verification: PASS
- managed policy / project override / XDG / hooks / metrics / migration / bootstrap tests: PASS
- `python3 -m pytest -q`: **20 passed**
- `test-validate-layout.sh`: 全19 fixture assertion を分割実行で確認
- staged fallback secret-pattern scan: PASS
- local `uv run --frozen pytest -q`: 初回は package gateway の HTTP 503 で未完了。2026-07-24 再実行では **20 passed**
- local gitleaks: binary が実行環境になく、ネットワーク取得も不可だったため未実行。CI の pinned gitleaks full-history scan は維持

## Live acceptance 実施結果（2026-07-24）

| 項目 | 判定 | 実機証跡 |
|---|---|---|
| Claude Code startup / managed source | PASS | stable 2.1.218、startup warning 0、`/status` で `Enterprise managed settings (drop-ins)` を確認 |
| bypassPermissions / auto mode lockout | PASS | 判定基準を「process の非ゼロ終了」ではなく「危険 mode が実効化されないこと」へ修正。`--permission-mode bypassPermissions` は manual へ強制降格し、auto も SessionStart 後の実効 mode は manual |
| malicious project settings | PASS | 判定基準を「session startup 自体の拒否」ではなく「managed policy を弱められず、起動前 preflight と PreToolUse で fail-closed」へ修正。`check-runtime.sh` は非ゼロ終了し、実 Claude session の `Bash(pwd)` は PreToolUse hook が拒否 |
| Claude Code Bash / `gh` approval | PASS | manual mode で `Bash(pwd)` の approval UI を確認。`gh auth status` も approval 後に実行され、認証状態が表示されたことを user acceptance で確認 |
| Sandboxed Git / helper workflow | PASS | 一時 repository 内で approval 後に `git add` と通常の `git commit` が成功。`uvw --version` は `uv 0.11.12`、`private-routing-locate` は managed allowRead 配下の routing path を返した |
| OS-level secret / private-tree deny | PASS | dynamic path で `.env.live-acceptance` は `Permission denied`。child process からの synthetic `~/.aws` marker と dynamic path の synthetic `~/.cache` marker は host に実在する一方、sandbox 内では `FileNotFoundError` / `No such file or directory` となり内容は非表示 |
| Sandbox unavailable fail-closed | PASS | process-local の隔離 PATH で `bwrap` / `socat` を不可視にすると Claude Code は exit 1。debug log に `sandbox.failIfUnavailable is set — refusing to start without a working sandbox.` を確認 |
| Codex CLI / plugin approval notation | PASS | Codex CLI smoke、strict config load、GitHub connector tool、`approval_mode = "approve"` を確認 |

## Live acceptance 最終判定

当時は全項目 PASS、残件なし。現行状態は冒頭の post-acceptance owner override を参照。

## 適用

```bash
git am agents-toolkit-modernization-final_8.patch
sudo ./scripts/install-managed-policy.sh --apply
./bootstrap.sh --apply
./bootstrap.sh --check
./scripts/check-runtime.sh
```
