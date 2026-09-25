# Routing eval（近代化 Phase 5、2026-09-25〜26）

integration 環境（host `mini`、候補 `modernize/phase-7`）で、過去の委任の Issue を base commit から解き直し（replay）、Claude main と Codex の route を比べた。題材は [`docs/eval/replay-tasks.md`](../eval/replay-tasks.md) の T1〜T6（private repo の Issue。対応表は private overlay にある）。

## 方法

- **Codex の実装担当**: 題材ごとに同じ契約（goal は Issue の本文、scope は参照修正から決めた paths、必須 check は `uv run pytest -q`）で `codex-delegate` を実行し、`verify-delegation`（gate）で判定した。route だけを変えた: gpt-6-astra の low / medium、gpt-6-sol の medium。
- **Claude main**: 同じ Issue と制約を `claude -p` に渡し、直接実装させた（1回 4 USD まで。owner 決定）。fable/high と opus/medium は全6件、fable/xhigh は D9 用に T1、T5、T6。
- **Codex の explorer**: 3題材（T2、T5、T6）で「変更が必要な files と functions」を read-only で答えさせ、参照修正の `src/` の files と照合した。gpt-5.6-terra と gpt-6-luna、どちらも medium。
- **指標**: 必須 check の合否、scope 外の変更ファイル数、diff の行数、継続を促した回数（単発の実行なので全件0）、token、所要時間、Claude の費用。参考として、参照修正の test file を実装後の tree に当てた結果も記録した（関数名などの interface が違うと失敗するので、合否には使わない）。
- **互換性**: D1 の候補（opus/medium）で、`claude --bg` から委任を1件通した。

## 結果

### 条件ごとの集計

| condition | runs | check PASS with changes, in scope | ref tests pass rate | USD total | mean sec | output tokens |
|---|---|---|---|---|---|---|
| fable-high | 6 | 6/6 | 86% | 15.96 | 271 | 127,719 |
| fable-xhigh | 3 | 3/3 | 48% | 11.33 | 422 | 102,278 |
| gpt-6-astra-low | 6 | 6/6 | 84% | 0.00 | 234 | 36,206 |
| gpt-6-astra-medium | 6 | 6/6 | 56% | 0.00 | 258 | 40,727 |
| gpt-6-sol-medium | 6 | 6/6 | 56% | 0.00 | 313 | 55,268 |
| opus-medium | 6 | 6/6 | 56% | 5.52 | 147 | 88,808 |

- 成功は「必須 check が PASS、変更あり、scope 外の変更0件」。
- T3 は最初、scope に `scripts/dashboard.py` が無く（Issue が dashboard の変更を求めていた）、Codex は3条件とも `out_of_scope_path` で停止し、Claude は scope の中だけで完了した。題材の誤りとして scope を直し、T3 は全条件でやり直した（上の表はやり直した結果。初回の Claude の費用 4.16 USD は下の合計に含む）。
- fable/xhigh の T6 は 4 USD の上限で打ち切られたが、その時点で必須 check は通っていた。

### 実行ごとの結果

| task | condition | outcome | check | files | lines | out of scope | ref tests pass/total | tokens in/out | USD | sec |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | fable-high | success | PASS | 5 | 84 | 0 | 16/16 | 483,481/8,339 | 1.41 | 133 |
| T2 | fable-high | success | PASS | 6 | 376 | 0 | 0/1 | 725,866/14,787 | 2.05 | 204 |
| T3 | fable-high | success | PASS | 8 | 665 | 0 | 0/1 | 1,260,274/30,697 | 3.48 | 374 |
| T4 | fable-high | success | PASS | 7 | 836 | 0 | 0/1 | 866,112/31,150 | 3.64 | 367 |
| T5 | fable-high | success | PASS | 2 | 202 | 0 | 22/24 | 668,220/14,692 | 1.97 | 196 |
| T6 | fable-high | success | PASS | 7 | 500 | 0 | 0/1 | 1,071,760/28,054 | 3.41 | 354 |
| T1 | fable-xhigh | success | PASS | 4 | 413 | 0 | 2/16 | 827,564/35,000 | 3.56 | 442 |
| T5 | fable-xhigh | success | PASS | 2 | 249 | 0 | 18/24 | 710,035/35,197 | 3.72 | 424 |
| T6 | fable-xhigh | error_max_budget_usd (error) | PASS | 9 | 513 | 0 | 0/2 | 944,591/32,081 | 4.06 | 399 |
| T1 | gpt-6-astra-low | completed / gate PASS | PASS | 5 | 19 | 0 | 15/16 | 250,986/2,252 | - | 104 |
| T2 | gpt-6-astra-low | completed / gate PASS | PASS | 5 | 150 | 0 | 0/1 | 319,081/4,231 | - | 186 |
| T3 | gpt-6-astra-low | completed / gate PASS | PASS | 6 | 249 | 0 | 0/1 | 494,920/8,281 | - | 299 |
| T4 | gpt-6-astra-low | completed / gate PASS | PASS | 6 | 342 | 0 | 0/1 | 700,353/9,737 | - | 351 |
| T5 | gpt-6-astra-low | completed / gate PASS | PASS | 2 | 95 | 0 | 23/24 | 329,776/3,869 | - | 179 |
| T6 | gpt-6-astra-low | completed / gate PASS | PASS | 7 | 218 | 0 | 0/2 | 535,643/7,836 | - | 282 |
| T1 | gpt-6-astra-medium | completed / gate PASS | PASS | 4 | 73 | 0 | 2/16 | 371,347/4,639 | - | 192 |
| T2 | gpt-6-astra-medium | completed / gate PASS | PASS | 4 | 155 | 0 | 0/1 | 320,356/4,277 | - | 175 |
| T3 | gpt-6-astra-medium | completed / gate PASS | PASS | 6 | 257 | 0 | 0/1 | 450,663/9,370 | - | 329 |
| T4 | gpt-6-astra-medium | completed / gate PASS | PASS | 6 | 386 | 0 | 0/1 | 703,050/9,552 | - | 344 |
| T5 | gpt-6-astra-medium | completed / gate PASS | PASS | 2 | 111 | 0 | 23/24 | 328,101/3,964 | - | 171 |
| T6 | gpt-6-astra-medium | completed / gate PASS | PASS | 8 | 337 | 0 | 0/2 | 754,951/8,925 | - | 337 |
| T1 | gpt-6-sol-medium | completed / gate PASS | PASS | 4 | 79 | 0 | 2/16 | 815,888/8,051 | - | 251 |
| T2 | gpt-6-sol-medium | completed / gate PASS | PASS | 4 | 88 | 0 | 0/1 | 470,935/6,763 | - | 185 |
| T3 | gpt-6-sol-medium | completed / gate PASS | PASS | 6 | 222 | 0 | 0/1 | 1,146,353/10,846 | - | 297 |
| T4 | gpt-6-sol-medium | completed / gate PASS | PASS | 4 | 233 | 0 | 0/1 | 1,530,429/11,683 | - | 335 |
| T5 | gpt-6-sol-medium | completed / gate PASS | PASS | 2 | 152 | 0 | 23/24 | 1,177,246/7,883 | - | 245 |
| T6 | gpt-6-sol-medium | completed / gate PASS | PASS | 6 | 176 | 0 | 0/2 | 1,710,148/10,042 | - | 567 |
| T1 | opus-medium | success | PASS | 4 | 166 | 0 | 2/16 | 365,469/7,766 | 0.58 | 89 |
| T2 | opus-medium | success | PASS | 3 | 196 | 0 | 0/1 | 473,477/7,374 | 0.56 | 78 |
| T3 | opus-medium | success | PASS | 8 | 546 | 0 | 0/1 | 917,919/24,456 | 1.25 | 219 |
| T4 | opus-medium | success | PASS | 6 | 617 | 0 | 0/1 | 1,461,200/22,159 | 1.31 | 216 |
| T5 | opus-medium | success | PASS | 2 | 126 | 0 | 23/24 | 672,108/9,015 | 0.69 | 104 |
| T6 | opus-medium | success | PASS | 8 | 473 | 0 | 0/2 | 1,146,127/18,038 | 1.14 | 177 |

### explorer の比較

| task | explorer | reference src files found | extra files named | tokens in/out | sec |
|---|---|---|---|---|---|
| T2 | gpt-5.6-terra | 3/3 | 0 (src) | 511,263/4,492 | 117 |
| T2 | gpt-6-luna | 2/3 | 1 (src) | 68,570/969 | 57 |
| T5 | gpt-5.6-terra | 1/1 | 0 (src) | 99,050/1,292 | 41 |
| T5 | gpt-6-luna | 1/1 | 0 (src) | 62,736/611 | 60 |
| T6 | gpt-5.6-terra | 4/4 | 1 (src) | 509,579/5,698 | 144 |
| T6 | gpt-6-luna | 4/4 | 1 (src) | 140,305/1,827 | 51 |

### 互換性（opus/medium を main にした場合）

- 完了通知が main に届き、gate は PASS（2 files、12 lines、check 1/1）。
- managed の deny で、Agent tool の選択肢から `codex:codex-rescue` が消える。
- Stop hook（`slack-notify-hook.sh stop`）と、command hook（pre-bash、post-edit など）が発火した。

## 解釈

- 6題材では、どの条件も成功率に差が出なかった。件数が少ないので、率の差で昇格を決めない（指示書 付録 E）。差が出たのは費用、時間、token である。
- Claude: opus/medium は fable/high と同じ成功率で、費用は約1/2.9、時間は約1/1.8。fable/xhigh は high より遅く高く、良くもならなかった。参照修正の test との一致は fable/high が高かった（T1 で 16/16）が、interface の偶然の一致に左右されるので決め手にしない。
- Codex: astra の low と medium の差は小さく（token が約1割少ない程度）、sol/medium は約2.3倍の token を使った。
- explorer: luna は参照修正の `src/` を 7/8 見つけ（terra は 8/8）、token は約1/4、時間は約1/2 だった。

## 決定（owner、2026-09-26）

- D1: Claude の main を Opus 5.5 にする（routing 表の claude-main と `claude/CLAUDE.md` の lead の行）。
- D9: effort はモデルの既定値（Opus 5.5 は medium、Fable 5.1 は high）。owner が live の `modelSettings` に設定する。
- Codex の実装担当は gpt-6-astra/medium を維持する。
- Codex の explorer を gpt-6-luna/medium にする（`codex/agents/explorer.toml` と `codex/AGENTS.md`）。
- `--cross` の Claude worker は、main と別のモデルにするため fable にする。
- hash に拘束された行（managed の env pin）は変えていない。

## 費用（D12: Phase 5 は 60 USD まで）

- Claude: 約 37.0 USD（上の表の15回。smoke の T5 と T3 のやり直しを含む。ほかに scope を誤った T3 の初回2回で 4.16 USD）と、互換性の確認 約 0.3 USD（transcript の token からの推定）。
- Codex: 実装担当 22回（上の表の18回、smoke の1回、T3 の初回3回）、explorer 6回。USD の上限は無く、token は上の表のとおり。
