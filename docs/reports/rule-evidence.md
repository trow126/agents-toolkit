# rules の根拠と確認日

rules には、現在有効な規則だけを書く。規則の根拠、確認した日、確認した version はここに記録する（指示書 §6.1、Phase 8 で rules から移した。2026-09-26）。

runtime の version が変わったら、下の行を discovery の再評価のきっかけ（指示書 §12）に合わせて確かめ直し、確認日を更新する。

| rule | 規則 | 根拠 | 確認日と version |
|---|---|---|---|
| `shared/rules/learnings.md`「共有ルールは原則ベースに保つ」 | 細則を列挙せず、原則で書く。Codex で遵守が下がったら、補足は `codex/` 側に足す | 2026-07 に karpathy-guidelines と decision-integrity を細則の列挙から原則ベースに圧縮し、`shared/rules/core-contract.md` に統合した。Claude 5 世代の context engineering の方針（細則よりモデルの判断に任せる）への準拠と、常時注入の削減が理由（`docs/plans/2026-07-23-agents-toolkit-modernization.md`） | 2026-07 |
| `claude/rules/settings-syntax.md`「引数プレフィックスマッチ」 | canonical は `Bash(git *)`。suffix の `:*` は末尾でのみ space-star と同等の legacy-equivalent で、deprecated とは断定しない | Claude Code の permission の公式仕様と、permission dialog が space-star を生成する挙動 | 2026-07-23 |
| `claude/rules/settings-syntax.md`「sandbox は settings.json への write を deny」 | sandbox は全 scope の settings.json（symlink の解決を含む）への write を built-in で deny する。linked worktree では main repo と共有する `.git` への write を許可し、`hooks/` と `config` は deny する | 公式の sandboxing docs | Claude Code v2.1.210 以降 |
