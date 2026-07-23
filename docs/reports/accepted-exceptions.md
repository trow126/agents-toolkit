# Accepted exceptions（承認済み例外の証跡 — 2026-07-24、適合性レビュー M-01/M-03 対応）

要件からの逸脱を要件所有者の承認つきで管理する台帳。承認の正本はセッション会話ログであり、本書はその転記（transcribed record）である。再レビューで所有者が本書を含む成果物を受け入れることが追認に相当する。失効条件を満たした例外は削除するか、要件書の改訂へ反映する。

| 項目 | EX-001 | EX-002 |
|---|---|---|
| 対象要件 | 「Agent Skills 準拠の新しい skill を 1 つだけ追加」(PDF Phase 4) | 「learnings の常時注入廃止」と常時 context の計測・報告 (PDF Phase 1/3) |
| 逸脱内容 | skill directory 純増 2 件: `claude/skills/break-consensus`(new behavior — 要件指定の 1 件) + `codex/skills/python-quality`(**relocation** — AGENTS.md 常時インラインの遅延ロード先。新規挙動なし) | `autoMemoryEnabled: true` を維持(Claude Code 組み込み auto memory による session 単位の知見注入が常時 context に加算され得る) |
| 承認者 | 要件所有者(T-row) | 要件所有者(T-row) — **2026-07-24 追認済み**(「有効のまま例外承認」を選択) |
| 承認日 / 発言 | 2026-07-23 「例外で良い」(ATK-010 の指摘に対する回答) | 2026-07-24 追認(設計経緯: v2 以降 CLAUDE.md に「新しい継続的な知見は native auto memory に保存する」と明記し、5 回のレビューを通過した設計) |
| 理由 | new **behavior** は 1 件のみ。python-quality は既存 AGENTS.md 内容の移設で、削減(−33.9%)を成立させる遅延ロード先として必要 | 常時 learnings import(2 経路)廃止の受け皿。static import と異なり蓄積は agent 自身の知見で、credential・private routing・runtime state の読込ではない(要件の禁止対象と交差しない)。`/knowledge-audit` で棚卸し可能 |
| 計測 | metrics: `claude_skills` / `codex_skills`(純増を隠さない) | metrics: `auto_memory_enabled: yes` を明示。注入量は machine 蓄積依存で static 計測不能(導入直後 0)。実機チェックリストで session 開始時の実測を行う |
| 失効条件 | 要件書が「新規 behavior 1 件」へ改訂された時点、または python-quality を AGENTS.md へ戻した時点 | `autoMemoryEnabled: false` へ変更した時点、または要件書が auto memory の扱いを明記した時点 |
| 関連 | 報告書 §3.6 / inventory-matrix §3 | 報告書 §3.2 / inventory-matrix §5(learnings 行)・§集計 |
