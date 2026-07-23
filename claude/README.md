# Claude Code configuration

[agents-toolkit](../README.md) の Claude Code 用 source。user directory には `install/manifest.tsv` の対象だけを symlink し、security policy は別途 OS-managed scope へ root-owned file として導入する。

## 構成

- `CLAUDE.md`: 常時 instruction、単一 owner と routing の最小契約
- `settings.json`: model、effort、status line、plugin、`autoMemoryEnabled: false` などの**非 security** user preference
- `managed-settings.json`: permission、sandbox、credentials、hooks、`permissions.disableBypassPermissionsMode`、top-level `disableAutoMode`、`requiredMinimumVersion: 2.1.218`
- `bin/`: deterministic helper。`project-policy-gate` は project/local security override を拒否する
- `hooks/`: managed policy からのみ登録される lifecycle / PreToolUse hook
- `rules/`, `agents/`, `skills/`: path-scoped knowledge、specialist、manual skill

## 導入

### 前提

- Claude Code 2.1.218 stable 以上
- Linux / WSL2: `bubblewrap` と `socat`
- `jq`, Python 3, Git
- GitHub workflow を使う場合のみ、認証済みの `gh`

```bash
sudo apt-get install bubblewrap socat jq   # Ubuntu / Debian / WSL2
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

- `bypassPermissions` と auto mode は managed policy で無効
- `sandbox.enabled: true`, `failIfUnavailable: true`, `allowUnsandboxedCommands: false`
- managed `permissions.ask: ["Bash"]` + `autoAllowBashIfSandboxed: false`: **組み込み read-only command を含む全 Bash は sandbox 内外を問わず標準 approval を経る**
- managed `permissions.allow` は `Agent`, `Read(**)`, `Edit(**)`, `WebSearch` のみ。Bash allow は0件
- `gh *` は credential 利用のため sandbox 外だが、managed `ask: ["Bash"]` により `gh auth status` を含む全 `gh` operation を ask にする
- pre-allowed domain は0件。`WebFetch(domain:...)` allow も置かない
- `denyRead` で private tree を遮断し、`~/.claude/bin`, `~/.claude/skills`, `~/.config/agents-toolkit` だけを narrow `allowRead` で再開
- `.env`、credential、`.git/config`、`.git/hooks/**` は managed deny。literal command は PreToolUse hook でも事故防止する
- `git commit --amend` は hook で over-block 側に拒否。history rewrite はユーザーが sandbox 外で明示実行する

`Read(**)` / `Edit(**)` は project path を対象とする。Bash、network、外部副作用は approval を伴うため、従来の「低プロンプト」動作より安全側に変更される。

## uv と Git

sandbox 内の Python tooling は `~/.claude/bin/uvw` を使用する。wrapper は uv の cache/data/config を session temp へ向け、private tree の denyRead を緩和しない。

```bash
~/.claude/bin/uvw run --frozen pytest -q
~/.claude/bin/uvw run ruff check .
~/.claude/bin/uvw run mypy .
```

`.git/config` / `.git/hooks/**` write は deny のため、`git config`, `git init`, `git remote add` は手動 shell で実行する。通常の `git add` / `git commit` は live acceptance test の対象。

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

static test では managed policy、project override、XDG、hook、metrics、inventory、release mode を検証する。WSL2/Claude Code 実機での OS-level deny、approval UI、startup warning、Codex CLI は別途 live acceptance が必要。

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
