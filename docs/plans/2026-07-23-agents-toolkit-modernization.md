# agents-toolkit 近代化レポート（v9 / 2026-07-24）

## 判定

**Historical v9 remediation / acceptance: COMPLETE**
**Current permission/sandbox posture: OWNER OVERRIDE ACTIVE (EX-003)**

2026年時点の Claude Code / Codex CLI / Agent Skills に合わせ、(1) 継ぎ足された常設機構の証拠ベース縮約、(2) manual-only innovation skill `break-consensus` の追加、(3) permission / sandbox / hook の fail-closed 化を実施した。

v9 は再レビュー指摘 **B-01 / C-02 / H-03 / H-04 / M-04 / M-05** を修正し、2026-07-24 に fail-closed policy の全 live acceptance を完了した。その後、repository owner が「完全に以前どおり: bypassPermissions に戻す」と明示したため、現行 managed policy は `bypassPermissions` 既定・confirmation 省略・sandbox 無効へ変更された。M-04/C-02 の prompt/sandbox 保護は現行 runtime には適用されず、EX-003 の owner override として管理する。過去の acceptance 証跡は履歴として保持する。

## Requirements source / baseline

- normative source: `260722_2151_001.pdf`
- SHA-256: `dc5fe5b333f0d0fda91fec72745ad458b3217e2be49a7b44c3093eb73287fdda`
- manifest: `docs/requirements/source-manifest.sha256`
- verifier: `scripts/verify-requirements-source.sh /path/to/260722_2151_001.pdf`
- searchable outline: `docs/requirements/requirements-transcription-260722.md`
- baseline commit: `7d193c2` (`baseline: pristine agents-toolkit-master from zip`)
- baseline evidence: `docs/reports/baseline-2026-07-23.txt`, SHA-256 `7ec80713c1b631a5add4b03f4f4acd12bbe77f0b24dd896e3f39e94c94e27a58`

PDF は15ページで、p.15 の `Stage 5: Forced Heterogeneity` 冒頭2文で終了する。Stage 6–7 は PDF p.12 §4.1 の「外部調査による既視感排除」「反証可能性評価」「最小コスト実験」を reversible な実装段階へ分解した**非規範マッピング**であり、PDF に存在しない追加要件としては扱わない。

## Before → after metrics

再現:

```bash
scripts/measure-metrics.sh --before-ref 7d193c2 --after-ref HEAD
```

| metric | before | after | change |
|---|---:|---:|---:|
| combined static always-on bytes | 43,068 | 33,444 | **−22.3%** |
| Claude static always-on bytes | 19,952 | 18,153 | −9.0% |
| Codex AGENTS.md bytes | 23,116 | 15,291 | **−33.9%** |
| CLAUDE.md lines | 59 | 47 | −20.3% |
| Claude always-on rules lines | 68 | 27 | **−60.3%** |
| custom agents | 14 | 9 | **−35.7%** |
| Claude skills | 21 | 13 | **−38.1%** |
| Codex skills | 4 | 4 | ±0 |
| hook scripts / registrations | 9 / 9 | 7 / 8 | −22.2% / −11.1% |
| shared rules / Claude rules | 16 / 7 | 13 / 5 | −18.8% / −28.6% |
| generic review/progress/retrospective mechanisms | 16 | 8 | **−50.0%** |
| custom agent ↔ built-in overlap | 2 | 0 | **−100%** |
| full model pins | 1 | 0 | **−100%** |
| unconditional `/gh-start` delegation | 1 | 0 | **−100%** |
| always-on learnings paths | 2 | 0 | **−100%** |
| native auto memory | enabled | disabled | bounded/explicit |
| SessionStart message max | unbounded | 512 bytes | bounded |
| Phase 1 audited elements | — | 137 | one row per element |

combined static bytes は −22.3% であるが、要件の「約30%は方向性であり数合わせで価値ある機構を削らない」に従い、agents / skills / rules / handoff / duplicate / review mechanism を複数指標で縮約した。managed-scope contract の明文化により一部 instruction は増加している。

### Machine-readable after block

`tests/test-report-consistency.sh` は次のブロックを `measure-metrics.sh --repo .` の**全 key と完全一致**で照合する。
`claude_skills` と `codex_skills` は source directory 数ではなく、`install/manifest.tsv` が各 runtime へ配布する一意な skill 名を数える。

<!-- BEGIN metrics:after -->
```
claude_md_bytes: 4815
claude_md_lines: 47
claude_always_rules_bytes: 2484
claude_always_rules_lines: 27
claude_imported_shared_bytes: 10854 (9 files)
claude_always_on_total: 18153
codex_agents_md_bytes: 15291
codex_agents_md_lines: 208
combined_always_on_total: 33444
custom_agents: 9
claude_skills: 14
codex_skills: 18
hook_scripts: 7
hook_registrations: 8
shared_rules: 13
claude_rules: 5
output_styles: 4
inventory_audited_elements: 137
review_progress_retrospective_mechanisms: 8
custom_builtin_agent_overlaps: 0
full_model_pins: 0
tier_aliases: 9
permissions_allow_count: 4
permissions_ask_count: 0
permissions_deny_count: 87
bypass_permissions_default: yes
dangerous_mode_prompt_skipped: yes
sandbox_enabled: no
auto_mode_lockout_ok: yes
effective_preallowed_domains_count: 0
unsandboxed_query_capable_allows: 0
managed_bash_allows: 0
managed_policy_present: yes
managed_permission_lock_ok: yes
managed_hooks_lock_ok: yes
managed_read_lock_ok: yes
managed_domain_lock_ok: yes
sandbox_auto_allow_bash: yes
auto_memory_enabled: no
session_start_system_message_typical_bytes: 102
session_start_system_message_max_bytes: 512
post_compact_system_message_typical_bytes: 128
post_compact_system_message_max_bytes: 512
claude_session_start_injection_typical_bytes: 18255
claude_session_start_injection_max_bytes: 18665
unconditional_delegation_gh_start: 0
always_on_learnings_paths: 0
duplicated_principles_greppable: 0 (of 3 signatures; +2 manual-assessed pairs documented in report)
```
<!-- END metrics:after -->

## Phase 1 inventory / H-04

Canonical source: `docs/reports/inventory-elements.tsv`（137 unique rows）
Rendered review: `docs/reports/inventory-matrix.md`

各行は以下の11軸を持つ。

1. purpose
2. current necessity
3. built-in alternative
4. overlap
5. context load
6. false-positive risk
7. failure impact
8. verification
9. low-cost-model suitability
10. deterministic replacement
11. disposition

settings、manifest、bootstrap、migration、validation、packaging、CI、issue/PR/review helper、external connection、runtime state、archive/legacy、各 test script を個別行で監査した。validator は schema、ID uniqueness、必須列、および operational tracked file の inventory coverage を機械検査する。

`review_progress_retrospective_mechanisms` は unique active path で定義し、after は8件:

- `claude/agents/code-reviewer.md`
- `claude/agents/plan-reviewer.md`
- `shared/skills/claude-code/gh-review/SKILL.md`
- `shared/skills/claude-code/plan-review/SKILL.md`
- `shared/skills/claude-code/pr-review/SKILL.md`
- `claude/hooks/pr-review-hook.sh`
- `claude/bin/gh-progress-sync.sh`
- `claude/bin/gh-retrospective.sh`

旧レポートの「5→0」は削除対象5件だけを数えた誤定義のため撤回した。

## Security architecture / C-02

### Managed/user split

- `claude/settings.json`: non-security user preference のみ。`autoMemoryEnabled: false`
- `claude/managed-settings.json`: owner 選択の `bypassPermissions`、disabled sandbox、credentials、hooks、top-level `disableAutoMode`、`requiredMinimumVersion: 2.1.218`
- `scripts/install-managed-policy.sh`: OS-managed drop-in へ exact root-owned copy を導入
- `bootstrap.sh`: managed copy の identity / owner / mode を確認するまで user symlink を作らない

Managed locks:

- `allowManagedPermissionRulesOnly: true`
- `allowManagedHooksOnly: true`
- `sandbox.filesystem.allowManagedReadPathsOnly: true`
- `sandbox.network.allowManagedDomainsOnly: true`

### Project/local gate

`claude/bin/project-policy-gate` は `<project>/.claude/settings.json` / `settings.local.json` の次を拒否する。

- `permissions`, `hooks`, `sandbox`
- managed-only control key
- shell/config redirect environment (`BASH_ENV`, `PATH`, `LD_PRELOAD`, `PYTHONPATH`, `NODE_OPTIONS`, `XDG_*` 等)
- invalid JSON、symlinked settings、project root 外へ解決する settings

実行箇所:

- `scripts/check-runtime.sh`: startup/doctor gate
- `claude/hooks/pre-bash-validate-hook.sh`: Bash PreToolUse 前、失敗時 exit 2
- `claude/hooks/config-change-hook.sh`: live settings change 後の gate

negative fixtures は `sandbox.enabled:false`、`excludedCommands:["cat *"]`、`allowRead:["~/.claude"]`、project/local permission allow、`BASH_ENV` injection を個別に拒否する。

## Current Bash / network / gh policy

- `permissions.defaultMode: "bypassPermissions"`
- `skipDangerousModePermissionPrompt: true`
- `permissions.ask`: **0**
- `sandbox.enabled: false`
- `sandbox.failIfUnavailable: false`
- `sandbox.allowUnsandboxedCommands: true`
- `permissions.allow` / `ask` / `deny` と sandbox filesystem/network は現行 runtime の enforcement ではない
- managed hooks と project-policy gate は事故防止として維持するが、完全な security boundary ではない

v9 の全 Bash approval、bypass lockout、fail-closed sandbox は当時の acceptance 対象としては成立していたが、EX-003 により現行 policy では意図的に supersede された。

## XDG / H-03

custom XDG の waiver/accept flag を削除した。`XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` は標準 path と realpath-equivalent の場合のみ許可する。

- trailing slash / `..` を正規化
- relative path を拒否
- custom absolute path を拒否
- obsolete `--accept-custom-xdg` を拒否
- test HOME と XDG を各 test で隔離し、親 process の XDG を継承しない

## Context / skills

- auto memory: disabled
- learnings: on-demand
- SessionStart/PostCompact output: JSON-safe、各512 bytes以下
- new behavior skill: `claude/skills/break-consensus` の1件のみ
- Python quality guidance: `codex/references/python-quality.md`（非 skill）
- active accepted exception: 1 (`docs/reports/accepted-exceptions.md`, EX-003)

`break-consensus` は manual invocation、Consensus Map、Assumption Destruction、Remote Mechanism Transfer、Forced Heterogeneity、独立 novelty audit、反証可能な minimum experiment を実装する。通常の bug fix / incident / migration / simple implementation へ自動適用しない。

## Re-review response

| ID | remediation | static status |
|---|---|---|
| B-01 | PDF hash を添付原本に一致させ、content-addressed manifest/verifier を追加。self-approval / circular ratification を削除 | **CLOSED** |
| C-02 | security policy を OS-managed scope へ移動。managed-only locks + project/local runtime gate + negative fixtures | **HISTORICALLY CLOSED; prompt/sandbox enforcement is SUPERSEDED by EX-003** |
| H-03 | custom XDG acceptance path を削除し、正規化後の standard path 以外を fail-closed | **CLOSED** |
| H-04 | 137-row one-element/one-row audit、11軸 schema、operational coverage validator、正しい8件 metric、hook bytes | **CLOSED** |
| M-04 | managed `ask: ["Bash"]`、Bash allow 0、sandbox auto-allow false により全 `gh` と read-only Bash を approval gate へ | **HISTORICALLY CLOSED; SUPERSEDED by EX-003** |
| M-05 | current-state 表記を v9 へ統一し、XDG test を hermetic 化 | **CLOSED** |

## Static validation

Expected release gates:

```bash
bash -n $(git ls-files '*.sh')
PYTHONPYCACHEPREFIX="$(mktemp -d)" python3 -m py_compile $(git ls-files '*.py')
for f in $(git ls-files '*.json'); do jq empty "$f"; done
./scripts/validate-layout.sh
./shared/bin/sync-shared-rules.sh --check
for t in tests/test-*.sh; do env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME "$t"; done
(cd claude/skills/python-refactor-analysis && uv run --frozen pytest -q)
./scripts/package-release.sh --check
```

Release check additionally refuses a dirty/index-divergent tree and packages tracked HEAD only.

## Historical live acceptance status（2026-07-24 / pre-EX-003）

判定基準を次のように実挙動へ合わせる。

- bypass / auto lockout は process の非ゼロ終了ではなく、指定しても危険 mode が実効化されないことを合格条件とする。
- malicious project settings は session startup 自体の拒否ではなく、managed policy を弱められず、起動前 preflight と PreToolUse で fail-closed になることを合格条件とする。

確認済み:

1. Claude Code stable 2.1.218、startup warning 0、managed source が `Enterprise managed settings (drop-ins)`
2. `--permission-mode bypassPermissions` と auto の指定後も実効 mode は manual
3. malicious project settings を `check-runtime.sh` が非ゼロ終了で拒否し、実 Claude session の Bash を PreToolUse hook が拒否
4. `Bash(pwd)` と `gh auth status` の approval UI、および approval 後の `gh auth status` 実行
5. 一時 repository 内の `git add` / 通常の `git commit` と、`uvw` / `private-routing-locate` helper
6. dynamic `.env`、child process の synthetic credential tree、dynamic path の synthetic private tree に対する OS-level deny
7. process-local の隔離 PATH で `bwrap` / `socat` を不可視にした際の exit 1 と `failIfUnavailable` 拒否ログ
8. Codex CLI smoke と plugin `approval_mode` 記法

当時の最終判定は全項目 PASS / **COMPLETE**。EX-003 適用後の現行 runtime は prompt/sandbox に関する 2、4、5、6、7 の保証を持たない。

## Installation / breaking changes

```bash
sudo ./scripts/install-managed-policy.sh --apply
./bootstrap.sh --apply
./bootstrap.sh --check
./scripts/check-runtime.sh
```

- slash command: `/gh:*` → `/gh-*`
- patch は mailbox series のため `git am agents-toolkit-modernization-final.patch`
- 現行 owner policy では Bash を含む permission prompt は表示しない
- custom XDG は非対応
- project/local security settings は非対応
- `.env.example` も deny 対象。必要なら `env.example` へ改名
- managed policy の変更は source review → root-owned file 再導入が必要

## Version history

v1–v7 は初期近代化と security hardening、v8 は最初の適合性レビュー対応。v9 は再レビュー B-01/C-02/H-03/H-04/M-04/M-05 を解消した。過去版の設計判断は git history に保持し、current-state 本文には SUPERSEDED な launcher、custom XDG waiver、auto memory exception、`gh auth status` allow を残さない。
