# Replay eval の題材

近代化 Phase 5 の routing eval で使う題材。どれも、実際に `/gh-codex-drive` で委任した private repo の過去の Issue を、修正前の base commit から解き直す。公開 repo には匿名化した行だけを置き、repo 名、Issue、base commit、参照修正の対応表は private overlay（`~/.config/agents-toolkit/eval/tasks/T*.json`、追跡しない）に置く。

- 必須 check は、どの題材も repo の test 全体（`uv run pytest -q`）。base の状態で全件が通ることを確かめてある。
- scope は、参照修正の diff から決めた。Issue に書かれた運用作業（データの backfill、報告の再生成、本番の確認）は対象外とし、契約と prompt に明記する。
- 参考の指標として、参照修正の test file を実装後の tree に当てた結果も記録する（関数名などの interface が違うと失敗するので、合否の判定には使わない）。

| ID | 種類 | 参照修正の規模 | scope_paths | 必須 check |
|---|---|---|---|---|
| T1 | 設定の既定値が上流 API で無視される不具合 | 6 files, +42/-15 | `src/**`, `tests/**`, `config.yaml`, `instances/**` | `uv run pytest -q` |
| T2 | 処理の失敗が下流の生成物を止める結合の分離 | 9 files, +306/-12 | `src/**`, `tests/**` | `uv run pytest -q` |
| T3 | 採番の責務を LLM からサーバ側へ移す仕様変更 | 9 files, +650/-72 | `src/**`, `tests/**` | `uv run pytest -q` |
| T4 | 集計の入力窓を単日から複数日に広げる機能追加 | 6 files, +582/-15 | `src/**`, `tests/**` | `uv run pytest -q` |
| T5 | 再起動後に失われる in-memory 状態の再構築 | 2 files, +204/-31 | `src/**`, `tests/**` | `uv run pytest -q` |
| T6 | 外部 CLI の解決失敗と分類の堅牢化 | 13 files, +362/-121 | `src/**`, `tests/**` | `uv run pytest -q` |
