---
paths:
  - "**/settings.json"
  - "**/settings.local.json"
---

# Claude Code Settings 構文ルール

## Permission 構文

- `Bash:*`, `Read:*`, `WebFetch:*` は**無効な構文**
- ツール全体を許可するには `"Bash"`, `"Read"` 等（`:*` なし）
- 引数プレフィックスマッチ: trailing space-star `Bash(git *)` を canonical 表記とする。suffix `:*`（`Bash(git:*)`）は末尾でのみ space-star と同等に認識される legacy-equivalent（deprecated と断定しない。permission dialog は space-star を生成する。確認日 2026-07-23）
- no-space wildcard（例 `Bash(npm run test*)`）は word boundary を持たず任意の後続文字列に match するため、allow には使わない（validator が拒否する）

## Settings 階層

- 評価順: deny > ask > allow
- documented scope: managed > CLI 引数 > project local（`<project>/.claude/settings.local.json`）> project > user（`~/.claude/settings.json`）。**user-level の `~/.claude/settings.local.json` という scope は存在しない**
- マージ規則: **scalar 値は高優先スコープが override** し、**array-valued settings は一般にスコープ間で連結・重複排除**される。permission rules（allow/ask/deny）だけでなく、`sandbox.filesystem.allowWrite` 等の filesystem arrays、`sandbox.credentials` の deny arrays、network arrays も連結される（＝低優先スコープの deny/ask は高優先スコープから除去できない。feature 固有の例外は当該公式仕様を優先）
- 運用方針: permission・hook・sandbox は root-owned OS-managed settings に一元管理する。user settings は非 security preference のみ。project / project-local に `permissions`・`hooks`・`sandbox` または shell/config redirect env を置くと runtime gate が fail-closed で拒否する

## Permission rule と sandbox の連動（見落とすと事故になる）

- `Read()`/`Edit()` の deny path は sandbox filesystem へ統合され、**OS-level で Bash と child process にも適用される**。広い deny は tool 自身の I/O を壊す（例: `Edit(.git/**)` deny は `git add`/`git commit` の `.git/index.lock` 作成を阻害する。保護は `.git/config`・`.git/hooks/**` に限定する）
- `WebFetch(domain:...)` の allow は WebFetch だけでなく **sandbox Bash の network domain も pre-allow** する。「事前許可 domain ゼロ」を保証するなら WebFetch allow も置かない
- `Edit()` の allow path は `sandbox.filesystem.allowWrite` と同様に write 許可を与える
- path prefix は permission rule（`//abs`・`/`=project 相対・`~/`）と sandbox filesystem（`/abs`・`~/`・無 prefix=project root / user settings では `~/.claude`）で**構文が異なる**
- sandbox は settings.json（全 scope・symlink 解決込み）への write を built-in で deny する。linked worktree では main repo 共有 `.git` への write を許可しつつ `hooks/`・`config` は deny する（v2.1.210+/公式 sandboxing docs）

## Managed policy installation

- `claude/managed-settings.json` は `install/manifest.tsv` で symlink しない。`scripts/install-managed-policy.sh --apply` が OS-managed drop-in へ root-owned copy を配置する
- bypass lockout は `permissions.disableBypassPermissionsMode`、auto mode lockout は **top-level** `disableAutoMode`。後者を `permissions` 配下へ置くと無効 entry として strip され得るため validator が拒否する
- `bootstrap.sh` は managed copy の hash/mode/owner を検証してから user symlink を作る
- project settings による `excludedCommands` 等の array 追加は managed-only switch がないため、`project-policy-gate` が file 自体を拒否する
