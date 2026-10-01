# Routing eval: gpt-6.1-sol と gpt-6-astra（Codex の実装担当、2026-10-01）

Codex の実装担当（`codex-implementer`）の route を、現行の gpt-6-astra/medium と gpt-6.1-sol の low / medium / xhigh で比べた。gpt-6.1-sol は Codex CLI 0.159 から使えるようになったモデルで、外部の評価（Artificial Analysis Coding Agent Index v1.5、OpenAI の DeepSWE v1.1）では、Astra と同程度の成績を数分の1のコストで出すと報告されている。2026-09-26 の eval（[`2026-09-26-routing-eval.md`](2026-09-26-routing-eval.md)）では全条件が 6/6 で差が出なかったため、今回は難度の高い題材を加えた。

## 方法

- 環境: host `mini`（Tailscale 経由の SSH）、Codex CLI 0.159.3、agents-toolkit `136cde7`。mini の Claude の設定は変えず、Codex の既定値と `[agents]` を live に揃え、`toolkit-implementer` profile、`~/.codex/AGENTS.md`、`~/.claude/hooks` だけを link した（`bootstrap.sh` は mini の user settings にある security policy の key で止まるため使っていない）。`~/.agents/skills` は配布していない。
- 題材: [`docs/eval/replay-tasks.md`](../eval/replay-tasks.md) の T1〜T10。T7〜T10 は今回追加した、参照修正が約 750〜1,550 行の題材。
- 条件: astra/medium（現行）、sol61/low、sol61/medium、sol61/xhigh。題材ごとに各2回、計80回。どの回も base から clone し直した。
- 契約: goal は Issue の本文、scope は題材の `scope_paths`、必須 check は `uv run pytest -q`。運用作業と scope 外の docs 等の更新は non_goals に書いた。2026-09-26 の契約とは文面が違う（T6 の項を参照）。
- 判定: `codex-delegate` で実行し、`verify-delegation`（gate）で判定した。参考として参照修正の test file を実装後の tree に当てた（interface が違うと collection の段階で失敗するので、合否には使わない）。
- 実行 script と記録: `atk_eval_run.py` が1回ずつ `results.jsonl` に記録した。script、結果、diff、盲検 review の採点と対応表は private overlay（`~/.config/agents-toolkit/eval/results/2026-10-01/`、追跡しない）に残し、mini の評価環境は片づけた。

## 結果

### 条件ごとの集計（20回ずつ）

| 条件 | gate PASS | stopped | 平均時間 | 平均 output tokens | 平均 input tokens（うち非 cache） | 平均変更行数 |
|---|---|---|---|---|---|---|
| astra/medium | 20/20 | 0 | 385s | 10,604 | 883,761（66,910） | 391 |
| sol61/low | 18/20 | 2 | 325s | 8,203 | 763,735（54,532） | 255 |
| sol61/medium | 20/20 | 0 | 451s | 12,162 | 1,035,390（70,001） | 413 |
| sol61/xhigh | 20/20 | 0 | 866s | 23,789 | 1,786,767（104,886） | 584 |

T7〜T10（難度の高い4題材、8回ずつ）だけで見ても、gate は全条件 8/8 だった。平均時間は astra/medium 572s、sol61/low 532s、sol61/medium 693s、sol61/xhigh 1,197s。

### 題材ごと（gate PASS / 2回、平均時間、平均 output tokens）

| task | astra/medium | sol61/low | sol61/medium | sol61/xhigh |
|---|---|---|---|---|
| T1 | 2/2, 133s, 2,546 | 2/2, 102s, 2,240 | 2/2, 126s, 2,787 | 2/2, 294s, 7,680 |
| T2 | 2/2, 218s, 5,422 | 2/2, 165s, 4,083 | 2/2, 250s, 6,260 | 2/2, 438s, 12,028 |
| T3 | 2/2, 392s, 10,986 | 2/2, 236s, 5,916 | 2/2, 414s, 11,733 | 2/2, 758s, 22,176 |
| T4 | 2/2, 347s, 9,602 | 2/2, 353s, 8,573 | 2/2, 370s, 10,229 | 2/2, 1,064s, 28,965 |
| T5 | 2/2, 216s, 5,802 | 2/2, 224s, 5,428 | 2/2, 224s, 5,656 | 2/2, 446s, 12,746 |
| T6 | 2/2, 260s, 6,949 | 0/2（stopped）, 40s, 768 | 2/2, 348s, 9,833 | 2/2, 877s, 24,411 |
| T7 | 2/2, 576s, 16,854 | 2/2, 410s, 10,886 | 2/2, 670s, 18,636 | 2/2, 1,016s, 28,859 |
| T8 | 2/2, 658s, 19,440 | 2/2, 600s, 15,275 | 2/2, 896s, 23,606 | 2/2, 1,498s, 40,064 |
| T9 | 2/2, 700s, 19,278 | 2/2, 790s, 20,394 | 2/2, 748s, 20,018 | 2/2, 1,032s, 27,740 |
| T10 | 2/2, 352s, 9,159 | 2/2, 329s, 8,470 | 2/2, 459s, 12,858 | 2/2, 1,242s, 33,223 |

参照修正の test は、T1（15/16）、T5（23/24）、T10（36/47）で全条件が同じ値になり、ほかの題材は interface の違いで collection に失敗した（sol61/xhigh の T7 の1回だけ 39/45）。品質の差は、この指標では見えない。

### T6 の stopped

T6 の Issue は systemd unit（`deploy/systemd/*.service`）への PATH の追加も求めているが、契約の scope は `src/**` と `tests/**` だけだった。sol61/low は2回とも、実装の前に scope 外の変更が必要だと判断して `stopped`（`out_of_scope_path`）を返し、systemd の変更を別タスクに分ける案を出した。ほかの条件は systemd に触れずに src と tests だけを実装して gate を通った。どちらも契約に反してはいない。2026-09-26 の eval で T6 が全条件で通ったのは、prompt に運用作業を対象外と明記していたためと考えられる。

### 利用枠と費用

- 80回の間、どの条件でも rate limit / usage limit に当たらなかった。
- Codex の credit の公表値（1M tokens あたり、Astra は input 250 / output 1,250、6.1 Sol は input 50 / output 250）で、非 cache の input と output だけから1回あたりを見積もると、astra/medium 約 30.0、sol61/low 約 4.8、sol61/medium 約 6.5、sol61/xhigh 約 11.2 credit になる。cache された input の credit 単価は確認していないので含めていない。

## 解釈

- 成功率では、今回も差が出なかった。難度の高い T7〜T10 でも全条件が gate を通ったので、gate の合否は天井に近い。件数も各条件 20回なので、率の小さな差で昇格を決めない（付録 E）。
- sol61/medium は、astra/medium と比べて時間が約17%、output tokens が約15% 多い。token の量はほぼ同じなので、credit の単価の差（約5分の1）がそのまま費用の差になる。見積もりでは約4〜5分の1。
- sol61/low は最も速く安いが、scope が曖昧な題材で止まりやすい（T6 で2回とも）。変更行数も少ない（平均 255 行）。止まること自体は契約に沿った挙動だが、実運用では再委任の手間が増える。
- sol61/xhigh は medium の約2倍の時間と token を使い、gate でも参照 test でも改善が見えなかった。
- diff の中身（設計、test の質、Issue の要件をどこまで満たしたか）は比べていない。gate は必須 check と scope しか見ない。

## 判断に向けて

- 費用と利用枠の面では、sol61/medium が astra/medium と同じ成功率で大幅に安い。
- 品質の差は、この eval では測れていない。判断の前に、T7〜T10 の diff を条件を伏せて review し、Issue の要件の充足と設計を比べることができる。

## 品質の比較（盲検 review、T7〜T10）

T7〜T10 の32件の diff を、条件を伏せて review した。題材ごとに候補8件（4条件×2回）の並び順を変えた2組を作り、それぞれ独立した reviewer（Claude Opus 5.5）が採点した。reviewer には Issue、契約の scope、参照修正の diff を渡した。採点は4軸（requirements: Issue の要件の充足、correctness: 不具合と回帰のリスクの低さ、tests: test が変更した振る舞いを検証しているか、design: 既存構造への適合）で、各0〜5点。

| 条件 | 採点数 | requirements | correctness | tests | design | 合計（20点） | 平均順位（8件中） | 2位以内 | 7位以下 |
|---|---|---|---|---|---|---|---|---|---|
| astra/medium | 16 | 4.19 | 3.31 | 4.12 | 2.94 | 14.56 | 5.31 | 2 | 6 |
| sol61/low | 16 | 3.62 | 2.62 | 3.56 | 3.12 | 12.94 | 6.38 | 0 | 9 |
| sol61/medium | 16 | 4.38 | 3.50 | 4.12 | 3.25 | 15.25 | 4.00 | 4 | 1 |
| sol61/xhigh | 16 | 4.94 | 3.69 | 5.00 | 2.94 | 16.56 | 2.31 | 10 | 0 |

題材ごとの平均合計:

| task | astra/medium | sol61/low | sol61/medium | sol61/xhigh |
|---|---|---|---|---|
| T7 | 14.00 | 10.25 | 14.00 | 17.00 |
| T8 | 13.75 | 13.25 | 15.75 | 15.50 |
| T9 | 16.75 | 14.25 | 16.00 | 17.00 |
| T10 | 13.75 | 14.00 | 15.25 | 16.75 |

同じ diff への2人の採点の差は、32件中23件で1点以内（最大4点）だった。

reviewer が既存の挙動を壊す回帰として挙げた欠陥:

- sol61/low: T7 の2回とも、main の LLM prompt（E は exit trigger も）を paper 台帳から作り、実発注とずれる。T9 の1回は、Brier の headline_odds_eligible filter を外す。T8 の1回は、cutoff の前に LLM の判断ごと skip する。
- sol61/medium: T7 の1回で、sol61/low と同じ main prompt の回帰。
- astra/medium: T8 の2回とも、締切を過ぎた推論の thread を放置する（次の cycle と並行して動く恐れ）。
- sol61/xhigh: T8 の1回で、LLM 層の API まで変える scope の広がり（回帰ではない）。

### 品質の解釈

- sol61/xhigh は T7、T9、T10 で最上位（T8 は sol61/medium と 0.25 点差の2位）で、条件ごとの採点16件のうち上位2位以内が10回あった。差の中心は requirements と tests で、要件の取りこぼしが少なく test が厚い。
- sol61/medium は astra/medium と同等以上（合計 +0.7、平均順位 4.0 と 5.3）。
- sol61/low は requirements と correctness が低く、回帰の指摘が最も多い。gate を通っても中身の品質が低いので、実装担当には向かない。
- 採点数が条件ごとに16で、reviewer も1種類のモデルなので、0.5点程度の差は誤差の範囲と見る。sol61/xhigh と sol61/low の差は、題材をまたいで一貫している。

## 決定（owner、2026-10-01）

- RE-1: Codex の実装担当を gpt-6.1-sol/xhigh に変える（`codex-route.env` と routing 表の codex-implementer の行）。fallback は gpt-6-astra/medium。
- divergent-codex（`--cross` の read-only worker、gpt-6-astra/medium）と、live の `~/.codex/config.toml` の既定値は変えていない。
