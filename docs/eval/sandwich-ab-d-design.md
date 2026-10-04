# A/B 設計（追加実験 D）: 受け入れテストを前提にした「Codex 実装 + Claude 軽量レビュー」と Opus 単独

状態: **凍結済み（2026-10-04、本番実行前）**。判定基準（§7）・アーム定義（§2）・反復数（§6）・harness・テンプレートは凍結コミット以降変更しない。凍結の記録は §11。

前回の設計書 [sandwich-ab-design.md](sandwich-ab-design.md)（凍結 `1a15c1e`、結果 [sandwich-ab-results.md](sandwich-ab-results.md) は REJECT on cost）を土台にする。この文書は前回との **差分** を書き、書いていないこと（題材、採点、盲検、費用の換算、停止条件など）は前回の設計書に従う。

## 1. 問い

> 受け入れテストを事前に与えた場合、Codex（gpt-6.1-sol）が実装し、テストが通るまで Codex 内で反復し、最後に Claude（Opus）が 1 回だけ軽量レビューする構成（D）は、同じテストを与えた Opus 単独（A'）に比べて、品質が同等で費用が下がるか。

前回の結果からの動機:

- 前回の B（Opus 計画 → Sol 実装 → Opus レビュー）は、Opus の計画だけで A の実装 1 本分を超える費用がかかり、費用比 2.34 で REJECT になった。工程内レビューは 32/32 が 1 回目で APPROVED、リーク指摘は 0/2 で、レビュー層の寄与は見えなかった。
- 前回の C（Sol 単独）は A の 0.70 倍の費用で、成功率が −18.8 pt だった。失敗の多くは受け入れテストで検出できる種類（interface 未実装、受け入れ 5/11 など）だった。
- そこで、「品質の担保を Opus の計画ではなく事前の受け入れテストに移し、Opus は安い軽量レビューだけを担う」構成が、Opus 単独より安く同等の品質になるかを測る。比較相手も同じテストを与えた Opus 単独（A'）にして、テストを与える効果そのものとアームの効果を分ける。

**前提（両アーム共通、明記）**: 受け入れテストを作る費用（人か別のセッションが書く）は、両アームに共通の前提として費用に入れない。この実験は「テストがすでにある状況」での実装方式の比較であり、テストを書く費用まで含めた総費用の比較ではない。

## 2. アーム

| arm（rid 上の id） | 構成 | Claude | Codex | コードを書く主体 |
|---|---|---|---|---|
| A'（`AP`） | `claude -p` の 1 セッションで、読む・実装する・test を回す。受け入れテストが作業ツリーに見え、実行できる | opus（`claude-opus-5-5`）/ medium | なし | Opus |
| D（`D`） | `codex-delegate` で Sol が実装。受け入れテストが見え、実行できる。gate（`verify-delegation`）が通るまで再委任（Codex 呼び出し最大 3 回）→ Opus が diff を 1 回だけ軽量レビュー（読み取り専用）→ must_fix があれば Codex に 1 回だけ修正依頼 → gate を再実行 | opus / medium（軽量レビューのみ） | gpt-6.1-sol / xhigh | Sol だけ |

- モデルと effort は前回と同じ（routing 表の claude-main と codex-implementer）。
- A' は前回の A と同じ `solo-prompt.md` を使い、本文の後ろに受け入れテストの説明（`templates/visible-tests.md`）を足し、check の一覧を §2.1 の可視 check にする。ツール集合も前回の A と同じ（`--tools Read,Glob,Grep,Edit,Write,Bash`）。
- D の Codex への契約は、前回の C と同じ `contract_for` で作るが、**goal に interface 一覧を必ず入れる**（前回の C の不具合の修正。§2.3）。goal の中身はタスク本文、`visible-tests.md`、interface 一覧の順で、A' のプロンプトと同じ文言である。計画（plan.md）は作らない。
- D の Opus はコードを編集しない。軽量レビューのツール集合は `Read, Glob, Grep` だけ（`--tools` で固定。Bash も持たないので、作業ツリーに書けず、テストも実行しない）。念のため前回と同じく前後で作業ツリーの指紋を比べ、変わっていれば `claude:readonly_write` を記録する。

### 2.1 受け入れテストの置き方（可視アーム共通）

- run の開始時に、overlay の受け入れテスト（`acceptance_tests`）を作業ツリーの `tests/_acceptance/` に `__init__.py` と一緒に置く（`place_visible_tests`）。git には追加しない（未追跡ファイル）。D の gate の baseline には含まれるので、置いたこと自体は Codex の変更に数えない。
- 可視 check（`visible_checks`）= 題材の必須 check ＋ `uv run pytest -q tests/_acceptance`。ただし必須 check のうち `ruff check` には `--extend-exclude tests/_acceptance` を付ける。受け入れテストは repo の lint 規約に合わせて書いていないので、付けないと R2・R4 で参照解でも必須 check が落ちる（凍結前に確認。§11.1）。両アームに同じ可視 check を渡す。
- 受け入れテストを変更・削除しないよう指示する（`visible-tests.md`）。run の終了時に原本の sha256 と比べ、変わっていれば `acceptance_tampered` に記録し、人手介入 `acceptance:tampered` として数える。**採点は常に overlay の原本で行う**（採点用の写しから `tests/_acceptance` を消してから必須 check を回し、その後に原本を置いて受け入れテストを回す）。したがって、受け入れテストを書き換えて通しても成功にはならない。
- 隠しテスト・ミュータントは前回どおり、どのアームにも見せず、採点時だけ写しに置く。

### 2.2 D の手順（事前に固定）

1. 契約を作り、`codex-delegate` で Codex を起動する（テスト段階 1 回目）。
2. `verify-delegation`（gate）を回す。gate は scope・差分予算・lint・Codex の完了報告・可視 check の全件を確かめる。
3. gate が通れば 4 へ。通らなければ、gate の violations を goal に追記して再委任する。テスト段階の Codex 呼び出しは **最大 3 回**。3 回目でも通らなければ終了し、人手介入 `tests:max_rounds` を記録する（軽量レビューはしない）。Codex が `stopped` を返したら、その時点で終了し `codex:stopped` を記録する。
4. 軽量レビューの直前に、隠しテストを写しで当てる（`round_grades`、記録だけで誰にも渡さない。§5.2 のリーク検出に使う）。
5. Opus が軽量レビューを **1 回だけ** 行う（`templates/light-review.md`、`review-verdict.schema.json` で出力を強制）。渡すのは、タスク本文、interface、gate が通ったという事実、base からの diff（`tests/_acceptance` は除く）。計画・Codex の完了報告・隠しテストは渡さない。
6. 判定の扱い:
   - APPROVED、または must_fix が 0 件 → 終了（採点へ）。
   - WARNING で must_fix が 1 件以上 → must_fix を goal に追記して Codex に **1 回だけ** 修正を依頼し、gate を再実行して終了。修正後に gate が落ちても、それ以上は反復しない（人手介入 `fix:gate_failed`）。
   - BLOCKED → 終了（人手介入 `review:BLOCKED`）。判定 JSON が読めない → 終了（`review:unparsed`）。
7. Codex 呼び出しは 1 run あたり最大 4 回（テスト段階 3 ＋ 修正 1）、Opus の呼び出しは最大 1 回。

### 2.3 前回の不具合（C の契約に interface 一覧が無い）の再発防止

- `contract_for` は goal に `## interface（変更しないこと）` の節を入れ、acceptance_criteria にも interface を列挙する。
- `sandwich_ab.py selftest`（モデルを呼ばない）が、全 ready 題材について次を確かめる。凍結前に 16 題材で PASS した（§11.2）。
  - D の契約から `codex-delegate` が実際に描くプロンプト（`delegation_common.render_prompt`）、A' のプロンプト、可視テスト無しの契約（前回の C の形）の 3 つに、interface の全項目が入っている。
  - D の契約と A' のプロンプトに、`tests/_acceptance` と可視 check の全部が入っている。ruff check が受け入れテストを除外している。契約が `contract.schema.json` に通る。
  - arm D の制御（gate 反復の上限、軽量レビュー 1 回、修正依頼 1 回、BLOCKED と修正後の gate 失敗の扱い）を stub で 5 通り通す。
- 負の対照として、前回（master）の `contract_for` を差し込んで selftest を回し、FAIL（interface 欠落 50 件、S11・S12 を含む）になることを確かめた。

## 3. 題材

前回と同じ 16 題材（S01〜S16、R1〜R4 の匿名表記。内訳と test の件数は前回の設計書 §3・§11.1）。overlay の題材 JSON・test・参照解・罠版・ミュータントは前回の凍結時から変えていない（§11.3 で sha256 が前回の記録と一致することを確かめた）。

可視アームの前提として、新しいサブコマンド `verify-visible <ID>` で次を機械検証した（§11.1）。

- base に受け入れテストを置いた作業ツリーで、可視 check のどれかが落ちる。
- 参照解を当てた作業ツリーで、可視 check が全部通る（D が gate を通れない題材が無いこと）。

前回の `verify-task`（base・参照解・罠版・ミュータント）も新しい eval_root でやり直した（採点の写しから `tests/_acceptance` を消す変更の回帰確認を兼ねる）。

## 4. 汚染の判定（定義の更新）

前回は、エージェントの記録（Claude の stream-json、Codex の exec jsonl）に overlay の test パス、`tests/_hidden`、`tests/_acceptance`、他 run の作業ツリー、盲検 pack・対応表、準備用ディレクトリが出てきた run を `contaminated` として除外した。

今回は受け入れテストを可視にするので、**汚染の対象を隠しテストに関わるものに限る**。

- 汚染とする: overlay のパス（隠しテスト・参照解・罠版・ミュータントの置き場。エージェントには一度も知らせない）、`tests/_hidden`、他 run の作業ツリー（rid の形 `S\d+-[A-Za-z0-9]+-r\d+`）、盲検 pack・対応表、`prep`・`dev`。加えて、D は工程の途中で隠しテストを当てるので、その出力（作業ツリーの隣の `*-hidden.xml`、採点用の写し `grade-*`）への言及も汚染とする。
- 汚染としない: 作業ツリーの `tests/_acceptance` への言及（可視アームでは見せているので当然出てくる）。
- 汚染の run は前回どおり集計から外し、報告する（再実行はしない。前回と同じく本番中の再実行規則は harness_error と rate limit だけ）。

## 5. 指標

### 5.1 主指標（判定に使う。定義は前回の §5 と同じ）

成功（必須 check・受け入れテスト全件・隠しテスト全件・scope 外の変更なし）、受け入れテスト合格率、隠しテスト合格率（leak 題材）、費用（API 料金表換算 USD。Claude は `total_cost_usd`、Codex は usage × config の公式単価で前回と同じ値）、所要時間、人手介入、盲検の品質（5 軸 25 点、Opus と gpt-6-astra の二重採点の平均）。

- 必須 check は、前回と同じく題材の必須 check（受け入れテストを含まない、ruff の除外も付けない）で採点する。可視 check はエージェントへの指示と D の gate にだけ使う。
- 受け入れテストを改変した run も、原本で採点する（§2.1）。

### 5.2 副次指標（報告だけ。判定に使わない）

- 前回の A・B・C との比較（同じ題材・同じ採点。盲検は pack が別なので並べない。前回は受け入れテストが不可視だった点が違う）。
- D の Codex 呼び出し回数の分布、テスト段階で gate が通った回、上限に達した run 数。
- 軽量レビューの指摘率（must_fix を出した run の割合、category 別）と有効性: 修正依頼の後に gate が通った割合、成功（採点）がレビュー前（`round_grades`）から最終で改善・悪化・不変だった run 数、レビュー前に隠しテストが落ちていたのに must_fix を出さなかった run 数、隠しテストが落ちていたときのリーク指摘率（前回の B と同じ定義）。
- 費用のうち軽量レビューが占める割合。
- 受け入れテストの改変の件数（アーム別）。

## 6. 手順

- eval_root は `~/eval-sandwich-d`（前回の `~/eval-sandwich` とは別。前回の結果には触れない）。設定は overlay の `config-d.json`（前回の `config.json` から eval_root と arms だけを変え、`light_review_toolset` を足した。単価・timeouts・盲検 reviewer・toolset は同じ値）。
- 16 題材 × 2 アーム（AP、D）× 2 反復 = **64 run**（A' 32、D 32）。`schedule --seed 20261005 --reps 2 --arms AP,D` で順番を乱数で混ぜる。並列 2。
- 盲検: `blind-pack --seed 11`（題材ごとに A'・D の 4 候補、2 組）→ `blind-review`（Opus effort high ツール無し、gpt-6-astra effort high read-only の二重採点。前回の §6.5 と同じ）。
- 集計: `ab_report.py --base AP --treat D --prior ~/eval-sandwich/results.jsonl`。
- 停止条件は前回の §6.3 と同じ（認証エラー、CLI の版の変化、harness エラーの 3 連続、ディスク不足）。rate limit の run は記録せず 30 分待ってやり直す。基盤エラーで止まった場合は、結果を保全して owner に報告し、再開は owner の判断による。
- 実題材での pilot はしない。代わりに玩具 repo（題材 S00・S98、別の eval_root）で、2 アーム × 1 run・盲検の二重採点・集計までを 1 回通した（§11.2）。結果は集計に入れない。
- 予算と時間の見込み: 前回の実績（A 102 秒、C 497 秒）から、A' ≈ 2 分、D ≈ 10〜15 分、並列 2 で 3〜5 時間。`claude_max_budget_usd_per_call` は前回と同じ 15 USD。

## 7. 判定基準（事前登録）

主比較は D と A'。前回の §7 と **同じ構造・同じ閾値** を、B → D、A → A' と読み替えて当てる。題材ごとに反復の平均をとり、題材を単位にした bootstrap（10,000 回、seed 1）。`ab_report.py` の `CRITERIA` は前回の値のまま変えていない。

**ADOPT（D を標準の選択肢にする）**: 次をすべて満たす。

| # | 基準 | 閾値 |
|---|---|---|
| 1 | 費用比 D / A'（題材ごとの平均費用の合計の比） | 0.70 以下、かつ bootstrap 95% 上限が 0.85 以下 |
| 2 | 成功率の差 D − A' | −5 pt 以上、かつ bootstrap 95% 下限が −15 pt 以上 |
| 3 | leak 罠のある題材で隠しテストが落ちた run 数 | D ≤ A' + 1 |
| 4 | 盲検の合計点の差 D − A'（25 点満点、Opus と gpt-6-astra の二重採点の平均） | −1.0 以上 |

**REJECT（Opus 単独のままにする）**: 費用比が 0.85 を超える、成功率の差が −10 pt を下回る、隠しテストが落ちた run 数が D ≥ A' + 3、のどれか。

**INCONCLUSIVE**: どちらでもない。前回と同じく、反復 3〜4 を追加して（`schedule --seed 20261006 --rep-start 3 --reps 2`、64 run）もう一度だけ判定し、それでも決まらなければ REJECT として扱う。追加の run は本番の 64 run の範囲外なので、owner の承認を得てから行う。

- 費用は受け入れテストを作る費用を含まない（§1 の前提）。
- 盲検の費用はアームの費用に入れない（前回と同じ）。

## 8. 前提作業（実施結果）

| # | 項目 | 結果 |
|---|---|---|
| 1 | CLI | 前回と同じ版（`claude --version`、`codex --version` は本番開始時に `versions.json` に記録し、各 run で照合） |
| 2 | 単価 | 前回の `config.json` と同じ値（OpenAI・Anthropic の公式料金表、2026-10-03 確認） |
| 3 | headless の権限 | 前回と同じ。managed policy の下では `--allowedTools` が効かないので `--tools` で集合を固定する。Slack 通知は `AGENTS_TOOLKIT_SLACK_NOTIFY=off` |
| 4 | 可視アームの前提 | `verify-visible` を 16 題材で PASS（§11.1） |
| 5 | interface の再発防止 | `selftest` PASS、負の対照で FAIL を確認（§2.3） |

## 9. 妥当性への脅威（前回の §9 に加えて）

- **受け入れテストの書き手は Opus**（前回と同じ準備用セッション）。テストを可視にしたことで、テストの癖が A' の実装に合う偏りはむしろ小さくなる（D も同じテストを見る）が、テストの解釈の癖が Opus に近い恐れは残る。
- **テストへの過適合**: 可視のテストに合わせた実装（特別扱い）で受け入れテストを通す恐れがある。隠しテスト（感度テストを含む）と盲検の「テストへの過適合」の観点（requirements・correctness 軸）で捉える。軽量レビューも観点 3 で見る。
- **A' の比較相手としての妥当性**: A' は「テストがあれば Opus 単独でも安く速く通る」可能性があり、D の費用比は前回の C/A（0.70）より不利になりうる。これは問いの定義どおりの比較である。
- **D の上限**: テスト段階 3 回・修正 1 回は実運用での人の介入点を模した値で、上限に当たった run は人手介入として数える。上限を変えた場合の結果はこの実験では分からない。
- **gate の差**: D は `verify-delegation`（scope・差分予算・lint も見る）が通るまで反復するが、A' は自分で check を回すだけで、差分予算や lint は外から強制されない。採点の成功の定義（§5.1）は両アームで同じ。
- **盲検 reviewer の自系統びいき**: 前回と同じ二重採点で扱う。前回は Opus reviewer に自系統びいきは見えなかった。
- **前回との比較（副次）**: 前回の A・B・C は受け入れテストが不可視で、実行時期・盲検 pack も違う。参考に並べるだけで、判定には使わない。

## 10. ファイル

| パス | 内容 |
|---|---|
| `docs/eval/sandwich-ab-d-design.md` | この設計書 |
| `docs/eval/sandwich-ab/templates/visible-tests.md` | 受け入れテストの説明（A' のプロンプトと D の契約に同じ文言で入れる） |
| `docs/eval/sandwich-ab/templates/light-review.md` | D の軽量レビューの基準 |
| `docs/eval/sandwich-ab/harness/sandwich_ab.py` | arm AP・D、`place_visible_tests`、`visible_checks`、汚染判定の更新、`selftest`、`verify-visible` を追加。`contract_for` に interface を追加 |
| `docs/eval/sandwich-ab/harness/ab_report.py` | `--base`・`--treat`・`--prior`、D の副次指標の節を追加（`CRITERIA` は不変） |
| `~/.config/agents-toolkit/eval/sandwich/config-d.json`（追跡しない） | この実験の設定 |
| `~/eval-sandwich-d/`（追跡しない） | mirror、作業ツリー、`results.jsonl`、盲検 pack |

## 11. 凍結の記録（2026-10-04、本番の run を 1 つも始める前）

### 11.1 題材の検証

新しい eval_root（`~/eval-sandwich-d`）で、凍結する harness を使って 16 題材すべての `verify-task` と `verify-visible` をやり直し、全件 PASS した。`check`（config-d.json）は `tasks: 16 (16 ready) OK`。

| 確認 | 結果 |
|---|---|
| `verify-task`（前回の §4.2: base・参照解・罠版・ミュータント） | 16/16 PASS（採点の写しから `tests/_acceptance` を消す変更の後も、前回と同じ判定） |
| `verify-visible`: base に受け入れテストを置くと可視 check が落ちる | 16/16（全題材で、必須 pytest 全体と受け入れテストの実行が落ちる） |
| `verify-visible`: 参照解で可視 check が全部通る | 16/16（R1・R3 は 2/2、R2・R4 は ruff を含む 3/3） |
| ruff の除外が必要か | 必要。除外なしで受け入れテストに repo の ruff を当てると、R2・R4 の 8 題材のうち 7 題材で違反が出た（1〜27 件）。除外しないと参照解でも可視 check が落ち、D は gate を通れない |

題材 JSON・test・参照解は変えていない（§11.3）。

### 11.2 harness の自己検査とスモーク

| 確認 | 結果 |
|---|---|
| `selftest`（config-d.json、16 題材） | PASS（契約・プロンプトの interface・可視テスト・可視 check、契約の schema、arm D の stub 5 通り） |
| 負の対照（前回の `contract_for` を差し込む） | FAIL（interface 欠落 50 件、S11・S12 を含む）。selftest が前回の不具合を検出できることを確認 |
| 玩具 repo のスモーク（S00・S98 × AP・D × 1、`~/eval-sandwich-smoke/root-d`） | 4 run すべて成功、除外 0、汚染 0、受け入れテストの改変 0。D は 2 run とも Codex 1 回で gate 通過、軽量レビューは 2 run とも APPROVED（nit 1 件ずつ）。Codex に渡ったプロンプトに interface 節と `tests/_acceptance` があり、gate の check に受け入れテストの実行が入ることを確認。A' は `uv run pytest -q tests/_acceptance` を実行していた。盲検の二重採点（8 採点）と `ab_report.py --base AP --treat D --prior` の集計・判定まで通った。結果は集計に入れない |
| スモークで見つかった不具合 | なし |
| 修正依頼の経路（must_fix → Codex 1 回 → gate 再実行） | スモークでは must_fix が出なかったので、実機では通っていない。制御は selftest の stub（`pass2-mustfix`、`pass1-mustfix-fixfails`）で確認した |
| CLI の版 | Claude Code 2.1.289（前回の本番は 2.1.288）、codex-cli 0.159.3（前回と同じ）。本番中は `versions.json` で固定し、変わったら止める |
| seed | 本番 `schedule --seed 20261005 --reps 2 --arms AP,D`、盲検 `blind-pack --seed 11`、INCONCLUSIVE の追加は `--seed 20261006 --rep-start 3 --reps 2` |

### 11.3 overlay のハッシュ

前回の凍結時（前回の設計書 §11.3）に記録した overlay の題材 JSON・test・patch・`config.json` の sha256 は、この凍結の時点で全ファイル一致した（88 ファイル、`sha256sum -c`）。今回追加した overlay のファイルの sha256 は次のとおり（パスは `~/.config/agents-toolkit/eval/sandwich/` からの相対）。本番の後に同じ値であることを確かめる。

```text
b95da9ed10e3f5c4446f3d40f8361ebee60a4d057f6ecc72378a4e6bb8b2a0f1  config-d.json
```
