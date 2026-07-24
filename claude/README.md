# Claude Code configuration

[agents-toolkit](../README.md) の Claude Code 用 source。user directory には `install/manifest.tsv` の対象だけを symlink し、owner policy は別途 OS-managed scope へ root-owned file として導入する。

## 構成

- `CLAUDE.md`: 常時 instruction、単一 owner と routing の最小契約
- `settings.json`: model、effort、status line、plugin、`autoMemoryEnabled: false` などの**非 security** user preference
- `managed-settings.json`: owner 選択の `bypassPermissions`、sandbox、credentials、hooks、top-level `disableAutoMode`、`requiredMinimumVersion: 2.1.218`
- `bin/`: deterministic helper。`project-policy-gate` は project/local security override を拒否する
- `hooks/`: managed policy からのみ登録される lifecycle / PreToolUse hook
- `rules/`, `agents/`, `skills/`: path-scoped knowledge、specialist、manual skill

## 導入

### 前提

- Claude Code 2.1.218 stable 以上
- `jq`, Python 3, Git
- GitHub workflow を使う場合のみ、認証済みの `gh`

```bash
sudo apt-get install jq   # Ubuntu / Debian / WSL2
cd ~/agents-toolkit
sudo ./scripts/install-managed-policy.sh --apply
./bootstrap.sh --apply
./bootstrap.sh --check
./scripts/check-runtime.sh
```

managed policy の導入先:

- Linux / WSL2: `/etc/claude-code/managed-settings.d/20-agents-toolkit-security.json`
- macOS: `/Library/Application Support/ClaudeCode/managed-settings.d/20-agents-toolkit-security.json`

`bootstrap.sh` は managed file が source と byte-identical、root-owned、group/world non-writable でなければ fail-closed で停止する。managed file は user symlink manifest へ入れない。

## Scope と project policy gate

Claude Code の scope は managed > CLI > project local > project > user。toolkit は security-critical key を managed scope に限定し、`allowManagedPermissionRulesOnly`、`allowManagedHooksOnly`、`sandbox.filesystem.allowManagedReadPathsOnly`、`sandbox.network.allowManagedDomainsOnly` を有効にする。

`<project>/.claude/settings.json` と `settings.local.json` には model 等の非 security preference だけを置ける。次は拒否対象:

- `permissions`, `hooks`, `sandbox`
- managed-only lock key
- `BASH_ENV`, `PATH`, `LD_PRELOAD`, `PYTHONPATH`, `NODE_OPTIONS`, `XDG_*` 等の shell/config redirect env

`scripts/check-runtime.sh` が起動前に、`project-policy-gate` が各 Bash の PreToolUse 前に同じ契約を検査する。unsafe file、invalid JSON、symlinked settings は exit 2 / non-zero で block する。project 固有の security 例外を追加せず、必要な変更は managed policy source をレビューして再導入する。

custom XDG base directory は非対応。`XDG_CONFIG_HOME` 等が `$HOME` 配下の標準位置と同値でなければ doctor が拒否する。

## Permission / sandbox 方針

- owner の明示選択により `permissions.defaultMode: "bypassPermissions"` と `skipDangerousModePermissionPrompt: true`
- `permissions.ask` は空。Bash、file tool、network、外部副作用を含め Claude Code の permission prompt は表示しない
- `sandbox.enabled: false`, `failIfUnavailable: false`, `allowUnsandboxedCommands: true`
- `bypassPermissions` では `permissions.allow` / `ask` / `deny` は enforcement layer にならず、sandbox の filesystem / network 設定も無効
- managed hooks と project-policy gate は引き続き実行する。literal `.env` 読み取り、block device write、`git commit --amend` 等を事故防止として拒否するが、完全な security boundary ではない
- permission/sandbox の旧 fail-closed 構成と live acceptance は履歴として文書に残すが、現行 runtime を保護する根拠にはしない

## uv と Git

`~/.claude/bin/uvw` は引き続き利用できるが、sandbox 無効の現行構成では必須ではない。wrapper は uv の cache/data/config を一時領域へ分離する。

```bash
~/.claude/bin/uvw run --frozen pytest -q
~/.claude/bin/uvw run ruff check .
~/.claude/bin/uvw run mypy .
```

Git 操作は permission prompt なしで実行される。リポジトリの Git workflow とユーザーの明示承認境界は引き続き守る。

## Context 注入

- native auto memory は無効
- learnings は常時 import せず、必要時に参照
- SessionStart / PostCompact の `systemMessage` は JSON-safe helper で各512 bytes以下
- `scripts/measure-hook-injection.py` が typical/max bytes を再現計測する

## 検証

```bash
./scripts/validate-layout.sh
./shared/bin/sync-shared-rules.sh --check
for t in tests/test-*.sh; do
  env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME "$t"
done
./scripts/package-release.sh --check
```

static test では owner 選択の managed bypass policy、project override、XDG、hook、metrics、inventory、release mode を検証する。2026-07-24 の approval/sandbox live acceptance は当時の fail-closed policy に対する履歴であり、その後の owner override により現行 runtime には適用されない。

## Skills

GitHub workflow: `/gh-start`, `/gh-pr`, `/gh-issue`, `/gh-review`, `/gh-index`, `/pr-review`, `/branch-cleanup`。

分析・utility: `/break-consensus`（manual only）, `/plan-review`, `/model-routing`, `/knowledge-audit`, `/config-audit`, `/python-refactor-analysis`。

新規 behavior skill は `break-consensus` の1件のみ。Codex の Python 品質ガイドは skill ではなく `codex/references/python-quality.md` へ遅延参照として配置する。

## Secret scanning

public repository への commit では gitleaks pre-commit hook と CI full-history scan を使用する。gitleaks がない場合、pre-commit は fail-closed で commit を拒否する。

```bash
git -C ~/agents-toolkit config core.hooksPath claude/githooks
```

## License

[MIT](../LICENSE)
