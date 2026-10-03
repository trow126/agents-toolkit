# A/B 設計: サンドイッチ手法（Opus 計画 → Sol 実装 → Opus レビュー）と Opus 単独

状態: **凍結済み（2026-10-03、本番実行前）**。前提作業（§8）は実施済み。判定基準（§7）・harness・テンプレートは凍結コミット以降変更しない。凍結の記録は §11。

## 1. 問い

サンドイッチ手法は、Claude Opus 5.5 が自己完結した計画ファイルを書き、GPT-6.1 Sol（Codex CLI）が新しいセッションで実装し、Opus が diff をレビューして APPROVED / WARNING / BLOCKED を返す手法である（最大 2〜3 往復）。主張は「Opus 単独よりコストが 30〜50% 減る」。懸念は次の 4 つ。

1. Sol のコード品質が Opus より低いのではないか
2. lookahead（未来情報のリーク）を Sol が仕込み、Opus のレビューも見落とすのではないか
3. 計画・レビュー・再委任のハンドオフのオーバーヘッドで、節約分が消えるのではないか
4. 結局、全部 Opus で良いのではないか

この eval は、定量トレーディング研究の実 repo の題材で、上の主張と懸念を事前登録した基準（§7）で判定する。

### 既存の資産との関係

- `/gh-codex-drive` は、すでに「Claude が契約を書き、Codex が実装し、Claude が gate と `/code-review` で確かめる」流れになっている。arm B はこれを、計画ファイルを明示し、レビュー判定を構造化した形に揃えたものである。実装の起動・gate は同じ `codex-delegate` と `verify-delegation` を使う。
- [2026-10-01 の routing eval](../reports/2026-10-01-routing-eval-sol61.md) は、Codex の中での比較（Astra と Sol）だった。Opus 単独との比較、ハンドオフ込みの総費用、リーク検出は測っていない。今回はそこを測る。
- 2026-10-01 の eval では gate の合否が天井に達し、差が出なかった。今回は gate（必須 check）に加えて、題材ごとの受け入れテストと隠しテストで判定する。

## 2. アーム

| arm | 構成 | Claude | Codex | コードを書く主体 |
|---|---|---|---|---|
| A: Opus 単独 | `claude -p` の 1 セッションで、読む・実装する・test を回す | opus（`claude-opus-5-5`）/ medium | なし | Opus |
| B: サンドイッチ | Opus が計画（read-only）→ `codex-delegate` で Sol が実装 → `verify-delegation` → Opus がレビュー（read-only）→ must_fix があれば指摘を付けて再委任（Codex は最大 3 回） | opus / medium（計画とレビュー） | gpt-6.1-sol / xhigh（routing 表の codex-implementer） | Sol だけ |
| C: Sol 単独（任意） | タスク本文から機械的に作った契約で `codex-delegate` を 1 回 | なし | gpt-6.1-sol / xhigh | Sol |

- モデルと effort は routing 表（`docs/contracts/model-routing.tsv`）の現行値に合わせた。claude-main は opus / medium、codex-implementer は gpt-6.1-sol / xhigh。
- arm B の Opus はコードを編集しない（`--disallowedTools Edit Write NotebookEdit`）。編集を許すと「Sol の実装品質」と「Opus の手直し」が混ざり、B の効果を測れない。
- 使えるツールの集合は `--tools` で固定する（A: Read, Glob, Grep, Edit, Write, Bash。B の計画・レビュー: Read, Glob, Grep, Bash）。managed policy が `defaultMode: bypassPermissions` と `allowManagedPermissionRulesOnly: true` なので、`--allowedTools` では権限を絞れない（§8 の 8）。`--tools` が無いと A が Skill・Task・Workflow 経由で Codex に委任できてしまい、「Opus 単独」でなくなる。B の Opus は Bash 経由の書き込みを禁止できないので、計画・レビューの前後で作業ツリーの指紋を比べ、変わっていたら人手介入 `claude:readonly_write` として記録する。
- arm C は、Opus の上下の層（計画とレビュー）に価値があるかを見るための参照である。C が B と同じ成功率でより安ければ、サンドイッチの Opus 部分は不要ということになる。
- すべてのアームに同じタスク本文、interface、scope、差分予算、必須 check を渡す（A には `templates/solo-prompt.md`、B と C には同じ内容を契約として渡す）。

## 3. 題材（16 件）

4 つの private repo から選んだ。公開 repo には匿名化した一覧だけを置き、repo 名、base commit、本文、テスト仕様は private overlay（`~/.config/agents-toolkit/eval/sandwich/tasks/S*.json`、追跡しない）に置く。

| repo | 内容 | 必須 check |
|---|---|---|
| R1 | 暗号資産の tick 特徴量・ラベル・逐次約定シミュレーション | `uv run pytest -q` |
| R2 | 日米セクターのリードラグ（rolling PCA、戦略、バックテスト、ファクター評価） | `uv run pytest -q`、`uv run ruff check .` |
| R3 | 日経 225 の需給フロー（イベントスタディ、gamma バックフィル、FRED 取り込み） | `uv run pytest -q` |
| R4 | 米国株の日次ボット（legacy バックテスト、research の as-of view、戦略） | `uv run pytest -q`、`uv run ruff check .` |

| ID | repo | 種類 | leak 罠 | 内容 | 受け入れテスト（自動） | 隠しテスト・ミュータント |
|---|---|---|---|---|---|---|
| S01 | R1 | 特徴量追加 | あり | rolling z-score 正規化オプション | 手計算一致、warm-up NaN、定数列 NaN、既定値で現行と一致 | 未来の摂動・接頭辞不変・感度 |
| S02 | R1 | ラベル | あり | triple-barrier（TP/SL/時間）ラベル | 既存ラベルとの一致、TP/SL 先着の手計算、同一 tick は SL 優先 | 時間バリアより後の摂動で不変、ギャップ行 invalid |
| S03 | R1 | バックテスト修正 | あり | 約定シミュレーションに take-profit と exit_reason | 既存テスト不変、TP 先着の手計算、再エントリー位置 | 決済後の価格の摂動で不変 |
| S04 | R1 | テスト追加 | あり | hypothesis による因果性プロパティテスト一式 | HEAD で pass、60 秒以内 | 既知リークのミュータント 4 種を落とせるか |
| S05 | R1 | リファクタ | なし | 時刻 ns 変換とトレード集計の重複解消 | 既存テスト pass、新ヘルパーの単体テスト、重複の残存を AST/grep で検査 | なし |
| S06 | R2 | テスト追加 | あり | コア層（PCA・戦略・アライメント・バックテスト）の perturbation テスト | HEAD で pass | 窓のずれ・shift(-1)・bisect の向き・全期間標準化のミュータント 4 種 |
| S07 | R2 | 特徴量追加 | あり | PCA の標準化に EWMA オプション | 既定値で完全一致、小 fixture の手計算 | t より後の摂動で不変、σ が r_t に依存しない |
| S08 | R2 | 時刻整合 | あり | ファクター回帰に「直前の米国セッション」への as-of 結合 | 既定値で既存テスト pass、連休 fixture の対応表 | 約定日当日以降の摂動で係数不変 |
| S09 | R2 | バックテスト修正 | あり | 取引コスト控除（約定日基準のターンオーバー） | cost=0 で完全一致、スキップ日を挟む手計算 | 将来の重み行を足しても過去 PnL 不変 |
| S10 | R3 | バックテスト修正 | あり | イベントスタディに公表ラグ（entry_lag_weeks） | lag=0 で決定論出力不変、lag=1 の手計算 | イベント週終値・ホライズン外の摂動で不変 |
| S11 | R3 | 特徴量追加 | あり | SQ までの日数と SQ 週フラグ（休日集合を引数に取る純関数） | 祝日・月跨ぎ・SQ 当日のケース | 将来の SQ 実績を改変しても不変、ファイルを読まない |
| S12 | R3 | リファクタ | なし | FRED 読み込みと atomic write の共通化（意味論の差を保つ） | 既存テスト pass、表駆動テスト | 呼び出し元ごとの旧挙動の回帰テスト |
| S13 | R4 | バックテスト修正 | あり | point-in-time ユニバース（生存者バイアスの除去） | membership=None で完全一致、未来の構成銘柄を買わない | 将来の構成変更・価格の摂動で過去の約定不変 |
| S14 | R4 | 特徴量追加 | あり | book-to-market × モメンタムの合成ルール（research） | 固定データで候補一致、パラメータ検証 | 公表前（available_at が未来）の行を無視 |
| S15 | R4 | バックテスト修正 | あり | ギャップ約定時の cash 不足を fail-closed で処理 | ギャップで完走し cash ≥ 0、ギャップ無しで完全一致 | 翌日始値の摂動で発注の意思決定が不変 |
| S16 | R4 | テスト追加 | あり | バックテストと本番戦略の因果性テスト | HEAD で pass | 窓 +1・終値約定・bfill・基準行ずれのミュータント 4 種 |

- 種類の内訳: 特徴量追加 4、バックテスト修正 5、テスト追加 3、リファクタ 2、ラベル 1、時刻整合 1。leak 罠ありは 14 件（うちテスト追加の 3 件はミュータントで判定）。
- テスト追加の題材（S04、S06、S16）では、「隠しテスト pass」を「エージェントが追加・変更した test が、隠しミュータントを全部落とす」と定義する（`grade` が `hidden` に `source: mutants` として入れる）。成功・基準 3（隠しテスト失敗 run 数）・隠しテスト合格率は、この定義で数える。
- 題材は、どれも合成データか repo 内の fixture で test でき、ネットワークを使わない。
- 本文には、実際の Issue に書く程度の時点整合の要件（「当該行を含む過去 w 行」など）は書くが、罠の答えや隠しテストの存在は書かない。

## 4. 受け入れテストと隠しテスト

### 4.1 置き場所と隔離

- test file は private overlay の `~/.config/agents-toolkit/eval/sandwich/tests/S*/` に置く（ディレクトリは 700）。どのアームの作業ツリーにも置かず、プロンプトにも入れない。
- 採点は、作業ツリーの写しに `tests/_acceptance/` と `tests/_hidden/` として置いて行う（`sandwich_ab.py` の `grade`）。作業ツリーそのものは変えない。
- 汚染検査: Claude の stream-json と Codex の exec jsonl に overlay の test パスが出てきた run は `contaminated` とし、集計から外す（再実行する）。

### 4.2 題材を ready にする条件

各題材の JSON は今は `status: "draft"` で、テストの仕様（`acceptance_spec`、`hidden_spec`）だけを持つ。harness は `ready` の題材だけを走らせる。ready にするには次をすべて満たす。

1. 受け入れテストと隠しテストを書く（interface は題材の `interface` に固定）。隠しテストは `templates/hidden_test_example.py` の 3 つの型（接頭辞不変、未来の摂動、感度）を組み合わせる。感度テストは、常に NaN を返すような空振り実装を通さないために必須とする。
2. 参照解（`reference`、overlay 内の patch）を作り、次を確かめる。
   - base で: 受け入れテストが fail する（新機能の題材）か、collection で落ちる。
   - 参照解で: 受け入れテストと隠しテストが全件 pass する。
   - 罠を踏んだ版（参照解に代表的なリークを入れた patch）で: 隠しテストが fail する。
3. テスト追加の題材（S04、S06、S16）は、ミュータント patch を用意し、base に当たることと、参照解の test がすべて落とすことを確かめる。
4. `sandwich_ab.py check` が通る。

1〜3 は `sandwich_ab.py verify-task <ID>` で機械検証する（base: 必須 check が通り、受け入れテストが全件は通らない／参照解: 必須 check・受け入れ・隠しが全件 pass、scope 外の変更なし／罠版 `trap.patch`（参照解の上に当てる）: 隠しテストが落ちる／テスト追加の題材: ミュータントが base に当たり、参照解が触る test ファイルの base 版では落ちない）。結果は `~/eval-sandwich/prep/<ID>/verify.json`。

参照解と test は、このどのアームとも別のセッション（人か、別に起動した Opus）が書く。同じ Opus が書いた test は arm A に有利に働く恐れがあるので、書き手を記録し、可能なら owner が目を通す。今回は、アームとは別に起動した準備用の Opus セッション（題材 2 件ずつ、8 セッション）が書いた（題材 JSON の `author`）。owner のレビューは受けていない（§9）。

## 5. 指標と測り方

| 指標 | 定義 | 測り方 |
|---|---|---|
| 成功 | 必須 check pass、受け入れテスト全件 pass、隠しテスト全件 pass（ある題材のみ）、scope 外の変更なし。この 4 つをすべて満たす | `grade` の結果（`final`） |
| 受け入れテスト合格率 | 受け入れテスト全件 pass の run の割合 | 同上 |
| 隠しテスト合格率 | leak 罠ありの題材で、隠しテスト全件 pass の run の割合 | 同上 |
| ミュータント検出率 | テスト追加の題材で、エージェントの test が落としたミュータントの割合 | `mutant_score` |
| レビュー指摘数（B） | 工程内レビューの findings の数（severity と category 別）と、Codex の往復回数 | review の JSON（`review-verdict.schema.json`） |
| リーク検出（B） | Codex の各 round の後に隠しテストを当て（記録だけで、誰にも渡さない）、隠しテストが落ちた round のうち、レビューが `leak_suspected` か `category: lookahead` を挙げた割合 | `round_grades` と `reviews` |
| 費用 | API 料金表換算の USD。Claude は `claude -p` の result の `total_cost_usd` を計画・実装・レビューで合計。Codex は exec jsonl の `turn.completed` の usage（非 cache 入力、cache 入力、出力）× config の単価 | `ab_report.py` |
| token | 上記の usage をそのまま。サブスクリプションの利用枠の消費の目安として、provider ごとに併記する | 同上 |
| 所要時間 | run の wall 時間と、段階ごとの時間（計画、Codex 各 round、レビュー各回、A の実装） | 同上 |
| 人手介入 | 実運用なら人が判断を求められた事象の数。Codex の `stopped`、レビューの BLOCKED、往復上限への到達、最終的な check の失敗、scope 違反、Claude の異常終了 | `interventions` |
| ハンドオフのオーバーヘッド（B） | B の総費用・総時間のうち、計画とレビューが占める割合 | 同上 |
| 盲検の品質 | §6.5 の 5 軸（各 0〜5、合計 25） | `blind-review` の採点 |

費用の注記:

- `total_cost_usd` は Claude Code が API 料金で換算した値で、サブスクリプションの実際の請求額ではない。両 provider とも「API 料金表で換算した USD」で比べることを事前に決めておく。サブスクリプションで使う場合は、token と利用枠の消費（rate limit に当たった回数）も併記する。
- Codex の単価は実行前に owner が公式の料金表で埋め、実行中は変えない（`config.json` の `prices_usd_per_mtok`）。未設定なら判定は PENDING になる。
- Codex の `output_tokens` が `reasoning_output_tokens` を含むかを、実行前に 1 run の jsonl で確かめる（§8）。含まない場合は `ab_report.py` の `run_cost` を直す。
- 2026-10-03 に公式の料金表で確かめた単価（USD / 1M token）:
  - gpt-6.1-sol（OpenAI 公式 developers.openai.com/api/docs/pricing、Standard、1 リクエストの入力 ≤272K）: input 2.00、cached input 0.10、cache write 2.50、output 10.00（>272K は 4.00 / 0.20 / 5.00 / 15.00）。Codex の usage はリクエスト単位でないので、短い文脈の単価で換算する（長い文脈のリクエストがあれば過小評価になる）。
  - Claude Opus 5.5（Anthropic 公式 platform.claude.com/docs/en/about-claude/pricing）: input 4、5 分 cache write 5、1 時間 cache write 8、cache hit 0.20、output 20。Claude 側は `total_cost_usd` をそのまま使い、この単価は照合用。
- Codex の usage には `cache_write_input_tokens` も出る（2026-10-03 のスモーク run で確認）。非 cache 入力 = input − cached − cache_write とし、cache write は 2.50 で換算する。感度分析として、非 cache 入力をすべて cache write 単価で換算した費用比も併記する（判定には使わない）。
- 盲検 review（§6.5）の費用は、アームの費用に入れない。

## 6. 手順

### 6.1 隔離

- repo ごとに `~/eval-sandwich/src/<repo>.git`（bare mirror）を作り、run ごとに `git worktree add --detach <base>` で作業ツリーを作る。1 run = 1 作業ツリーで、同じ作業ツリーを別の run で使い回さない。
- 各作業ツリーで `uv sync` を実行してから始める。元の repo の未コミットの変更（`scripts/` などにある）は mirror に入らない。
- `codex-delegate` の状態ファイルは作業ツリーごとの git-dir（`<gitdir>/agents-toolkit/`）に入るので、並列の run は干渉しない。

### 6.2 ハンドオフのファイル形式

| ファイル | 書く人 | 読む人 | 形式 |
|---|---|---|---|
| `plan.md` | Opus（B の計画） | Codex | `templates/plan.md` の 10 節。時点整合の制約（5 節）は時系列の題材で必須 |
| 契約 JSON | harness | `codex-delegate` | `gh-codex-drive` の `contract.schema.json`。goal にタスク本文と `plan.md` を入れる |
| Codex の完了報告 | Codex | Opus（レビュー） | `report.schema.json`（既存） |
| gate の evidence | `verify-delegation` | Opus（レビュー） | 既存 |
| レビュー判定 | Opus（B のレビュー） | harness | `templates/review-verdict.schema.json`。`claude -p --json-schema` で出力を強制 |
| 再委任の指摘 | harness | Codex | must_fix を契約の goal に追記（`[category] location: fix`） |

再委任の規則（事前に固定）: APPROVED、または WARNING で must_fix が 0 件なら終了。WARNING で must_fix があり、Codex が 3 回未満なら再委任。BLOCKED、判定 JSON が読めない、3 回目でも must_fix が残る、のいずれかなら終了し、人手介入として数える。

### 6.3 実行順のランダム化

- 16 題材 × 3 アーム × 2 反復 = 96 run。`sandwich_ab.py schedule --seed 20261003` で順番を乱数で混ぜ、時間帯や rate limit の影響がアームに偏らないようにする。seed は実行前にこの文書に記録し、変えない。
- 並列は 2（2026-10-01 と同じ）。rate limit に当たった run は記録せず、30 分待ってやり直す。
- 本番の前に、harness の動作確認として 2 題材 × 3 アーム × 1 反復の pilot を回す。pilot の結果は集計に入れない。pilot で harness を直した場合は、本番を始める前に直す（本番中は harness も基準も変えない）。
  - **2026-10-03 の決定**: owner の判断で、実題材での pilot は省略した。代わりに、実題材を一切使わない玩具 repo（題材 S00・S98、別の eval_root）で、3 アーム × 1 run・盲検の二重採点・集計までを 1 回通した（スモークテスト）。結果は集計に入れない。スモークで見つかった harness の不具合（§11.2）は凍結前に直した。
- seed: 本番は `schedule --seed 20261003`（16 題材 × 3 アーム × 反復 1〜2 = 96 run）。INCONCLUSIVE で反復を増やす場合は `schedule --seed 20261004 --rep-start 3 --reps 2`（反復 3〜4 の 96 run を後ろに足す）。どちらも観測前に固定した。
- 致命的な基盤エラーでは新しい run を始めずに止める: 認証エラー、CLI の版の変化（各 run の開始時に確かめる）、harness エラーの 3 連続、ディスク不足。止めた時点までの結果は `results.jsonl` に残る。

### 6.4 run の流れ

1. `check`: CLI、profile、template、題材の test file が揃っているかを確かめる（モデルは呼ばない）。
2. `schedule`、`run`: run ごとに作業ツリー作成 → アームの実行 → 状態ファイルの退避 → `grade` → 汚染検査 → `results.jsonl` に 1 行追記。
3. `blind-pack`、`blind-review`: §6.5。
4. `ab_report.py`: 集計と判定（§7）。

### 6.5 盲検 review

- 題材ごとに、全アーム・全反復の最終 diff（src と tests。lockfile と採点用の test は除く）をランダムな記号に置き換え、並び順を変えた 2 組を作る（`blind-pack`）。対応表 `blind-map.json` は reviewer に渡さない。
- reviewer には、アーム名、モデル名、時間、token、Codex の報告、計画、レビュー履歴を渡さない。採点基準は `templates/blind-review.md`（requirements、correctness、leakage、tests、design の 5 軸）。
- reviewer は Opus で、arm A と同じモデルである。自分の出力を好む偏りが A に有利に働く恐れがあるので、次のどちらかで補う（どちらにするかは §8 で owner が決める）。
  - 2 組のうち 1 組を、別系統のモデル（Codex の gpt-6-astra など、read-only）に採点させる。
  - 題材のうち 4 件（25%）を owner が自分で採点し、Opus の採点との一致を確かめる。
- **2026-10-03 の owner の決定: 別系統モデルによる二重採点**。上の 1 案目を強めた形にする。
  - reviewer は 2 系統: Opus（`claude-opus-5-5`、effort high、`claude -p --tools ""` でツール無し）と、Codex の gpt-6-astra（effort high、`codex exec -s read-only`、git repo の外の空ディレクトリで実行）。
  - 両者が **同じ盲検 pack の 2 組（v1、v2）の両方** を独立に採点する（候補 1 つにつき 4 つの採点）。どちらにも対応表・アーム名・モデル名を渡さない。Codex がコマンドを実行した採点は `_meta.used_tools` に記録する。
  - 主指標（基準 4）は、run ごとに「reviewer ごとの 2 組の平均」を reviewer 間で平均した値。両 reviewer の採点が揃わない run は主指標に入れない。
  - 一致度として、候補ごとの合計点の Pearson・Spearman 相関、平均絶対差、leakage 軸の「リークあり（≤2）」判断の一致率、reviewer ごとの基準 4 の可否と、その reviewer 間の一致を報告する。reviewer 間で基準 4 の可否が割れた場合は報告に明記するが、判定は主指標で行う（観測前に固定）。
  - 参考として、隠しテストが落ちた候補に各 reviewer が leakage ≤ 2 を付けた割合（盲検 reviewer のリーク検出力）も報告する。

## 7. 判定基準（事前登録）

主比較は B と A。題材ごとに反復の平均をとり、題材をまたいで比べる（対応のある比較）。信頼区間は題材を単位にした bootstrap（10,000 回、seed 1）。値は `ab_report.py` の `CRITERIA` と同じで、結果を見た後に変えない。

**ADOPT（B を標準にする）**: 次をすべて満たす。

| # | 基準 | 閾値 |
|---|---|---|
| 1 | 費用比 B / A（題材ごとの平均費用の合計の比） | 0.70 以下（30% 以上の削減）、かつ bootstrap 95% 上限が 0.85 以下 |
| 2 | 成功率の差 B − A | −5 pt 以上、かつ bootstrap 95% 下限が −15 pt 以上 |
| 3 | leak 罠のある題材で隠しテストが落ちた run 数 | B ≤ A + 1 |
| 4 | 盲検の合計点の差 B − A（25 点満点、Opus と gpt-6-astra の二重採点の平均。§6.5） | −1.0 以上 |

**REJECT（Opus 単独のままにする）**: 次のどれかに当たる。費用比が 0.85 を超える。成功率の差が −10 pt を下回る。隠しテストが落ちた run 数が B ≥ A + 3。

**INCONCLUSIVE**: どちらでもない。反復を 2 から 4 に増やして（新しい seed で schedule を追加して）、もう一度だけ判定する。それでも決まらなければ REJECT として扱う（変える側に立証責任を置く）。

参照の判断（arm C）:

- C が基準 2〜4 を A に対して満たし、費用が B より低ければ、「Opus の計画とレビューの層は費用に見合わない」と記録する（Sol 単独の採用は別の判断とし、この eval では決めない）。
- B と C の隠しテスト合格率の差と、B のレビューのリーク検出率（§5）を、懸念 2 への答えとして報告する。

基準 2 の −5 pt は、16 題材 × 2 反復では約 1.6 run に当たる。点推定だけでは偶然の 1〜2 run で決まってしまうので、bootstrap の下限（−15 pt）も合わせて課す。2026-10-01 の eval と同じく、率の小さな差だけで昇格を決めない。

## 8. 前提作業（owner の承認待ち）

実行はしていない。次を owner が承認・実施してから始める。

1. **Codex CLI の確認**: この WSL には `codex-cli 0.159.3` が `~/.npm-global/bin/codex` に入っていて、`toolkit-implementer` profile も `~/.codex/` に link されている。ただし `~/.npm-global/bin` は `.profile` と `.bashrc` でしか PATH に入らないので、非ログインの `bash -c` では見つからない。harness は `bash -lc` から起動する。
   - 入っていない環境に導入する場合の手順（runbook [`codex-cli-update.md`](../runbooks/codex-cli-update.md) に従う）:

     ```bash
     # 1. 実行中の委任と app-server broker が無いことを確かめる（runbook §1）
     # 2. 導入（npm の global prefix を ~/.npm-global にしている前提）
     npm install -g @openai/codex
     codex --version
     # 3. 認証（ブラウザでのログイン。owner が自分で行う）
     codex login
     # 4. toolkit の profile と hook を配布し、discovery で catalog に gpt-6.1-sol があることを確かめる
     ~/agents-toolkit/bootstrap.sh --check
     ~/agents-toolkit/scripts/discover-runtime.sh
     ```

   - 認証の状態（`codex login status`）と、catalog に `gpt-6.1-sol` があることは、owner が確かめる。
2. **単価の確定**: `config.json` の `prices_usd_per_mtok`（Codex）を公式の料金表で埋める。Claude は `total_cost_usd` を使う。
3. **Codex の usage の確認**: pilot の 1 run の jsonl で、`output_tokens` が reasoning を含むかを確かめる。
4. **test と参照解の作成**: §4.2 の手順で 16 題材を ready にする。書き手（人か、どのセッションか）を記録する。目安は題材あたり 1〜2 時間。
5. **R4 の運用規約**: R4 の `CLAUDE.local.md` に、運用系コードの変更を凍結する規約が残っている（期限は過ぎている）。S13 と S15 は運用系（バックテスト engine）に触れる。eval は mirror 上の使い捨て作業ツリーで行い、元の repo には一切書かないので規約には触れないと考えるが、owner が確認する。
6. **盲検 review の補強**: §6.5 の 2 案のどちらにするか。
7. **予算と時間**: 96 run。2026-10-01 の実績（sol61/xhigh で平均 866 秒）と、Opus 単独が同程度かかると仮定すると、並列 2 で 12〜16 時間程度。`claude_max_budget_usd_per_call`（既定 15 USD）を 1 回の上限にする。pilot の結果で見直す。
8. **headless の権限**: `claude -p` に渡す `--allowedTools` が managed policy（`claude/managed-settings.json`）と衝突しないかを pilot で確かめる。衝突したら config の tool 一覧だけを直す（managed policy は変えない）。

### 8.1 実施結果（2026-10-03、本番前）

| # | 項目 | 結果 |
|---|---|---|
| 1 | Codex CLI | `codex-cli 0.159.3`、`codex login status` = Logged in using ChatGPT。`discover-runtime.sh` で `codex-implementer: gpt-6.1-sol/xhigh is in the catalog` を確認。Claude Code は 2.1.288 |
| 2 | 単価 | 公式料金表で確認して config に記入（§5 の注記）。判定は PENDING にならない |
| 3 | Codex の usage | スモーク run の `turn.completed` で reasoning_output_tokens < output_tokens（例: 1,916 / 4,294）。output が reasoning を含む前提と整合する。`cache_write_input_tokens` も出るので換算に入れた |
| 4 | test と参照解 | §11.1 |
| 5 | R4 の運用規約 | owner の判断で S13・S15 を含める。mirror からの使い捨て作業ツリーだけで行い、元の repo には書かない |
| 6 | 盲検 review の補強 | 別系統モデルによる二重採点（§6.5） |
| 7 | 予算と時間 | owner 承認済み（12〜16 時間＋準備）。pilot は省略（§6.3） |
| 8 | headless の権限 | 衝突ではなく「効かない」: managed policy が `defaultMode: bypassPermissions`・`allowManagedPermissionRulesOnly: true` のため、`--allowedTools` に関係なく全ツールが許可される（haiku の小さな `claude -p` で確認）。`--disallowedTools` はツールを外すので効く。config に `claude_impl_toolset` / `claude_readonly_toolset` を足し、`--tools` で集合を固定した（managed policy は変えていない）。`--tools ""` で init の tools が空になることも確認 |
| — | Slack 通知 | managed の Stop hook が各 `claude -p` の終了で Slack 通知を予約するので、harness は `AGENTS_TOOLKIT_SLACK_NOTIFY=off` で子プロセスを起動する |

## 9. 妥当性への脅威

- **題材の作り手の偏り**: 題材の選定と test の仕様は Opus が書いた。Opus が書いた interface や test は、Opus の実装（A）に合いやすい恐れがある。§4.2 で書き手を分け、owner が目を通す。
- **指示ファイルの差**: R1 と R4 には `CLAUDE.md` があり、「特徴量は trailing 窓のみ」などの規律が書かれている。Claude はこれを読むが、Codex は `AGENTS.md` しか読まない。これは実運用と同じ条件なのでそのままにし、結果の解釈で触れる。B では計画がこの差を埋めるかどうかも見どころになる。
- **自動化された B と実運用の B の違い**: 実運用では owner が計画を直したり、WARNING を見て判断したりする。この eval は、その人手を入れない下限を測る。
- **サンプルの小ささ**: 16 題材 × 2 反復。小さな差は判定できない（§7 の bootstrap 下限で扱う）。
- **モデルとCLIの更新**: 実行中に CLI やモデルが更新されると比較が崩れる。開始時に `discover-runtime.sh` の snapshot を取り、`codex --version` と `claude --version` を各 run に記録し、途中で変わったら止める。
- **pilot の省略**: 実題材での pilot を省いたので、題材固有の基盤トラブル（依存の解決、長い test、rate limit）は本番で初めて表に出る。harness の記録・除外規則（harness_error、汚染、rate limit の再実行）で扱う。
- **test の書き手は Opus**: 準備用のセッションはアームと別だが、同じ Opus 5.5 である。owner のレビューは受けていない。受け入れテストの細部が Opus の実装の癖に合う恐れが残る（arm A に有利な方向）。準備担当には「本文から一意に決まることだけを検証する」よう指示し、判断は各題材の `prep_notes` に残した。
- **環境の差による check の修正**: R2 は gitignore された `data/` が mirror に入らず、既存 test 2 件が base でも落ちる。この 2 件だけを `--deselect` した必須 check を全アームに渡す（§11.1）。
- **盲検 reviewer のモデル**: 二重採点の一方は arm A と同じ Opus、もう一方は arm B・C の実装（gpt-6.1-sol）と同じ OpenAI 系の gpt-6-astra。どちらも自系統に甘い恐れがあり、両者の差そのものが偏りの手がかりになる。

## 10. ファイル

| パス | 内容 |
|---|---|
| `docs/eval/sandwich-ab-design.md` | この設計書 |
| `docs/eval/sandwich-ab/templates/plan.md` | 計画テンプレート（自己完結、10 節） |
| `docs/eval/sandwich-ab/templates/plan-prompt.md` | 計画担当への指示 |
| `docs/eval/sandwich-ab/templates/solo-prompt.md` | arm A への指示（B と C の契約と同じ内容） |
| `docs/eval/sandwich-ab/templates/review.md` | 工程内レビューの基準 |
| `docs/eval/sandwich-ab/templates/review-verdict.schema.json` | レビュー判定の JSON schema |
| `docs/eval/sandwich-ab/templates/blind-review.md` | 盲検 review の採点基準 |
| `docs/eval/sandwich-ab/templates/task.schema.json` | 題材 JSON の schema |
| `docs/eval/sandwich-ab/templates/hidden_test_example.py` | 隠しテスト（perturbation）の型 |
| `docs/eval/sandwich-ab/harness/sandwich_ab.py` | 実行・採点・盲検 pack の harness |
| `docs/eval/sandwich-ab/harness/ab_report.py` | 集計と事前登録の判定 |
| `docs/eval/sandwich-ab/harness/config.example.json` | 設定の例（overlay の `config.json` に写して使う） |
| `~/.config/agents-toolkit/eval/sandwich/`（追跡しない） | 題材 JSON（S01〜S16、draft）、test、参照解、`config.json` |
| `~/eval-sandwich/`（追跡しない） | mirror、作業ツリー、`results.jsonl`、盲検 pack |

harness は eval 専用の道具なので、`scripts/`（inventory の対象）ではなく `docs/eval/` に置いた。

## 11. 凍結の記録（2026-10-03、本番の run を 1 つも始める前）

### 11.1 題材の準備結果

16 題材すべてが ready になった（除外 0 件）。最終確認は、凍結する harness で `verify-task` を 16 題材やり直し、`check` が `tasks: 16 (16 ready) OK` を返したこと。

| ID | 受け入れ | 隠し（またはミュータント） | 罠版で落ちた隠し | 準備時の修正（観測前） |
|---|---|---|---|---|
| S01 | 8 | 5 | 5/5 | なし |
| S02 | 11 | 4 | 1/4 | なし（同一ティックの TP/SL は、正の tp・sl では同時に成立しないので検査しない） |
| S03 | 10 | 5 | 1/5 | なし（同上） |
| S04 | 9 | ミュータント 4 | 3/4 を見逃す | ミュータント 2 種を差し替え: `closed="both"` と `side="left"` はリークにならず接頭辞不変テストで原理的に落とせないので、`is_buyer_maker` の `shift(-1)` と決定時刻の窓の符号反転にした |
| S05 | 19 | なし | — | 差分予算 9→15 files（本文の置き換え先だけで src が 9 ファイルになるため。参照解 11 files の 1.3 倍） |
| S06 | 4 | ミュータント 4 | 1/4 を見逃す | 必須 check の pytest で 2 件を `--deselect`（R2 共通）。本文に「PCA 由来の浮動小数の比較だけは atol 1e-12 程度の許容でよい」を追記（同一入力でも最下位桁が揺れ、check_exact では HEAD で pass できないため）。ミュータント 2 種を §3 の記述（窓のずれ・全期間標準化）に合わせて、t+1 行を含む窓と全期間の平均・標準偏差にした |
| S07 | 4 | 4 | 1/4 | 必須 check（R2 共通）。EWMA の重みとバイアス補正の 4 通りを許容 |
| S08 | 6 | 6 | 5/6 | 必須 check（R2 共通） |
| S09 | 5 | 5 | 3/5 | 必須 check（R2 共通）。ターンオーバーの係数 1 と 0.5 の両方を許容 |
| S10 | 16 | 58 | 37/58 | なし |
| S11 | 29 | 6 | 3/6 | なし |
| S12 | 21 | 13 | 4/13 | なし（隠しテストは本文の対象外の非公開関数名に依存する） |
| S13 | 4 | 5 | 1/5 | 必須 check の pytest で 1 件を `--deselect`（R4 共通） |
| S14 | 11 | 5 | 2/5 | 必須 check（R4 共通）。戻り値は list[str] と候補オブジェクトの list の両方を許容（interface と本文の記述が食い違うため） |
| S15 | 5 | 2 | 1/2 | 必須 check（R4 共通） |
| S16 | 4 | ミュータント 4 | 4/4 を見逃す | 必須 check（R4 共通）。本文を文字どおり読んだテストではミュータントを落とせない（合格率が低めに出る見込み、§9） |

- R2 共通: gitignore された `data/` が mirror に入らず、既存 test 2 件が base でも落ちるので、その 2 件だけを `--deselect` した。R4 共通: 同じ理由で `data/research/` を読む 1 件を `--deselect` した。全アームに同じ必須 check を渡す。
- テスト追加の題材は、本文が指定した test ファイル（`mutant_test_files`）だけにミュータントを当てる。S04・S06 では base の既存 test が一部のミュータントを落とすので、エージェントが既存の test ファイルを触っても加点しない。
- 参照解の差分予算超過は S05 だけだった。
- 各題材の判断の詳細は overlay の題材 JSON の `prep_notes`。test と参照解の書き手は、どのアームとも別に起動した準備用の Opus 5.5 セッション（題材 2 件ずつ、8 セッション）。

### 11.2 凍結前に直した harness の不具合と変更

| 変更 | 理由 |
|---|---|
| `--tools` でツール集合を固定、`AGENTS_TOOLKIT_SLACK_NOTIFY=off` | §8.1 の 8 |
| 採点の写しに `.venv` を持ち込まず、写しで `uv sync` する | editable install が元の作業ツリーの src を指し、写しに当てたミュータントが効かない |
| `git add` の pathspec から ignore 済みの `.venv` を外す | git が exit 1 を返し、採点が必ず落ちていた（スモークで発見） |
| `--json-schema` に渡す schema から `$schema` を外す | claude が draft 2020-12 の宣言を受け付けず、B のレビュー判定が必ず unparsed になっていた（スモークで発見） |
| 汚染検査の needle を `tests/_hidden`・`tests/_acceptance` に絞り、別 run の参照は rid の形（`S\d+-[A-Z]-r\d+`）だけを見る。`prep`・`dev`・盲検 pack も needle に加える | R4 の src に `_acceptance` を含む関数名がある。Codex は上位ディレクトリの `AGENTS.md` を探すので `runs/AGENTS.md` が出る（スモークで誤検出） |
| Codex の usage に `cache_write_input_tokens` を加える | §5 |
| テスト追加の題材の hidden をミュータントで定義、`mutant_test_files` | §3 |
| `verify-task`、`schedule --rep-start`、版の変化・認証エラー・連続エラー・ディスク不足での停止、B の read-only 呼び出しの書き込み検知、`blind-review` の二重採点、`ab_report.py` の一致度・token・オーバーヘッド・arm C の報告 | §4.2、§6.3、§6.5、§2 |

### 11.3 overlay のハッシュ

overlay は git 管理外なので、凍結時点の題材 JSON・test・patch・config の sha256 を下に記録する（パスは overlay の `~/.config/agents-toolkit/eval/sandwich/` からの相対）。本番の後に同じ値であることを確かめる。

```text
cecadd87966d2b44846554582b1ddde07ff9fff00c1d75978d41d4871f113129  config.json
d2ccb4b343f48c08bcc50ebbf3ad1fa11f2fcf2aa222e803669eadb6e595f303  tasks/S01.json
ff533d132f481d7bd3249aa34769ae2877af56754aaac411f12e917f509757e0  tasks/S02.json
d9c7f85635714803e52e6e1b6b752c874cc6942a6db1cb1f0329bbd33253ca79  tasks/S03.json
9e7d8c44433e3ae11abc262b99a4d3bb33440badbf63b02be2ffdb07b833a902  tasks/S04.json
53c461f2dc2e35e1d07b528d3d3647d78efc6bd9429bc06e2e41a3660e579f68  tasks/S05.json
6f0169b62ecda554b946e3b50e58fe03bd7b22a30209eda3493f9aa903f664e2  tasks/S06.json
7200efdc819a99e3dd542e9cc0aa69e1e7ec32c65eec01f7d2cf2306994cb5e3  tasks/S07.json
fee7451d0dca2c9e933138c2c0946a23955a0a282190eb45bc9e8917b36596cd  tasks/S08.json
4e452b727eb202de69760b3b7ea9107569f6a6dad20c6642bd11469f92e6cabc  tasks/S09.json
bf4a686f1caaf8c71696d429505c5bc834177738fbf92ebcc05086c279ec555e  tasks/S10.json
ade4fdeee87919578c0ae08ba09ba2f3243933c3116636bb3a9804916b5df133  tasks/S11.json
0da2aae4e35f6cd2d32e2a64871475ebeb74564f6eb96b3667d0234efe34cf9d  tasks/S12.json
ee985cb8a54d56a08c2904856147994e8098ba87282d874da573db7a90eee675  tasks/S13.json
c83659972c91d2b1a493341746a81634000b90fba68833b33ce91e22f5fa967d  tasks/S14.json
8c1b2ad00d33d61994882ffda828882e6372d44c17de95768a6a7c8944171371  tasks/S15.json
f7e85ca9e100437847924efd7989525342fee7ba7f36d67c4ecdaf51ce87d3b1  tasks/S16.json
3bb4e944f7cef460d565e910d2762fe2774d58f26dd896a8ca08beb04f32d0cf  tests/S01/reference.patch
ff4b0b3222fde3a3616a822ccf82ab1ef463ba02ec37255fe9f31e88ccfd7854  tests/S01/test_S01_acceptance.py
d578eca9a34e01ec7e5dff8f0807b5811948b5aa32d203fef54e5f173c90dae4  tests/S01/test_S01_hidden.py
a946968b9998d6ed0ffa6c76717bb87a66bbc56438c711ed887555ca85a6c05d  tests/S01/trap.patch
4f7c3b016fbb9b45fabb9e7a01538d5c11f1372ff5ff5df1733b9c535a876b7a  tests/S02/reference.patch
1301949fba5bfdebfae08b0018a41e84789913328627fbe00985cfbca9b18f5a  tests/S02/test_S02_acceptance.py
f40a81ec81cc60d736f48c8be3a13f418878a509a5122299f4957c79209b9e8e  tests/S02/test_S02_hidden.py
793aa966f88237eae6b5877e99630b5c247e95cd63333bbad60789c37ed59da1  tests/S02/trap.patch
39a231c1d91c88dbadee80824bd941104d2d1c308e2e3347fd7788b26cb35a49  tests/S03/reference.patch
6286d702d9effc0f111c72320a79cf53b5651b2089ba5b896be9afa9814fbbe9  tests/S03/test_S03_acceptance.py
32b906bf13dacf4cdbf7d3f488cbb0733389f0452600ccaf45b5b7c8683e02ed  tests/S03/test_S03_hidden.py
bcbb9978ff9ba88a18c9a31bee1566fe3bdb2214e10202a8cbaba5a30e98721b  tests/S03/trap.patch
7f136a16500463372696baacfa6be05d08983e5ad67b9dfd2274638d47e8fcb5  tests/S04/mutants/m1.patch
26009f0f7ed726f24975d3ef4973f049bac059055ffc941f375e83132a8bcecc  tests/S04/mutants/m2.patch
b99f99adbb11881fe164f8fd87bc567f2e6ba69eb126ec257a9848cb9d5c1f0f  tests/S04/mutants/m3.patch
b50239d9bf9e0c58e3f3a89d3f51871c322fe129d01a827b54f13110c48ec961  tests/S04/mutants/m4.patch
eecc1f8d21e96f0d2c8ef8a1b7aa45fcb470bb217d1f2b761791e60ef842210f  tests/S04/reference.patch
1f12572c5b37fc7d0fa548af128828a0c8d2d2578b3df575f5c69a2944f58f23  tests/S04/test_S04_acceptance.py
ae0f502165189a6847d6c7a87dd636d5202af125bee943c8a17ae2ce590c0482  tests/S04/trap.patch
b24d3bd1f52ab7e3371edef1e16dcfef1b6a1069d9bb72e7561699176330ec23  tests/S05/reference.patch
20d0dc5cfb95da88cef99bc315cbaf70d97d9074beeb9ef58fcfb174a83a0e0f  tests/S05/test_S05_acceptance.py
7c80ef73a9e0d73efb8186107ecc4df8def739edb2933f77f5927e6dc4b6db38  tests/S06/mutants/m1.patch
5498c94ed420885dfc19b4d035b7941abd861228746bc18a158ccc4c63594424  tests/S06/mutants/m2.patch
d3cc091c4fb6c4e6f38a388d1ba3e62b0f1d64891ee5ce715e7918215dcdcadb  tests/S06/mutants/m3.patch
05efb3bf67777702539df9418b6681356babc52fc1bf7991f93217156251fdca  tests/S06/mutants/m4.patch
43e056e50638a19dd62a146f32f217ce900c7f9666e4f26c147dd1c69bb3e5d7  tests/S06/reference.patch
2544ebfad8d63b014f31f0bd0bcb7b9bc7c9b7172f5a0355148b52656f32c0a9  tests/S06/test_S06_acceptance.py
30366a1dd137c1b8f7980aad7a67069ce3f05ce9944e4c297247998a19ad9403  tests/S06/trap.patch
d1a93854766f494516ab68bf2c87943796145c4ffe0ec977fec1008dabed0681  tests/S07/reference.patch
d739226eb6b458707164995fa924568a75c11d6fb9ee07f96792d834004e2c8f  tests/S07/test_S07_acceptance.py
4bbafb9a6f1fe75441f912302dcb91aaae65ec06f800092e78a6ce461837076f  tests/S07/test_S07_hidden.py
ac8c80c2269f8ab443380e9a14bea6b8bfb4a88aa0c28bc720742f77f33a03e5  tests/S07/trap.patch
452fce25c5cd9cb2c1d0d194b7f7a96a50045e9ef508d70cb1e87d9fde623325  tests/S08/reference.patch
e04d0d2ffd0962c41b731eaa9cc7a787733428f68cb789c7e2e60b2c694dc941  tests/S08/test_S08_acceptance.py
25db3d4b605595a19afcd16d6f1cead57132d0dd935f1b7e14b072a08d70c949  tests/S08/test_S08_hidden.py
433d73a472de9a8898ae77011753bcf41785280516916c20b503992763ada8c0  tests/S08/trap.patch
caa2485779ffe664168fe36acfe3d6a00629b0ea21c9dc8ad014d28dfd3243c1  tests/S09/reference.patch
74cac05582ffa097dcad5576856cad0bb8140c9325093774fb23b11a35264558  tests/S09/test_S09_acceptance.py
01f5d9aeaf190d253f301ca12a02eef4a3332221ee2ff86ff7869aebd93378b4  tests/S09/test_S09_hidden.py
46af3c3063eadb40fe093d9763a5513889a4150e83480e4f2fea02a0c5c1c312  tests/S09/trap.patch
a90c7aeb6ee04a0bbfe28c74f4b898e22c14679ac40abee9b421e6e3e3f5d8e4  tests/S10/reference.patch
e05ad0af209db2ef66bd4b58f8d35b5f224cc5c5dfbaa4c9fdbcd263b14d3d0d  tests/S10/test_S10_acceptance.py
76373370e58867fc4bebc02d6c4ab5e5939f59666951442be5e6f7f93e8b1035  tests/S10/test_S10_hidden.py
47db4b3ef19a9286839910fa6ea1fc480bcd9dbf104a4443fe10f2c49c99081d  tests/S10/trap.patch
b0b3b3dbeade2e01f07188200965649a74690ea70ae2f19545fd46128304e2ff  tests/S11/reference.patch
51bb07444d7a289e9ec4f87ead49e7145fb1555649fa09bbaa8f28ae77d1ec33  tests/S11/test_S11_acceptance.py
178b10ba2941ea7954665272cd59fa25adb9671bbc41b2b1b8fc56f62d71c493  tests/S11/test_S11_hidden.py
867778535b950b7388a43813b591ac788958d4ff4ab83d3fe0adb24666d7b947  tests/S11/trap.patch
4f53d42a81160be3657cf6daa10d3924721ca6f33cbbaac604535d53884e2a10  tests/S12/reference.patch
99bdbeca6bb9c522069e1f5cdfba2bac573c1efdb251eb2d07a65c650b9da2b5  tests/S12/test_S12_acceptance.py
89e249b11be4dcf82a6192970d63bb3c9743362702f1c04ce0c9d78c45e48464  tests/S12/test_S12_hidden.py
29d62078c32e73415cd4c621dd76e8e1a46c719c6ba752a5dbb9de5ed6c0bb8b  tests/S12/trap.patch
77327f1a861bef0f3b07652223374a59b829016afc36f2193d0e48a6f2c73f87  tests/S13/reference.patch
0217eea00db907aa1bbe12ff8c1e21d37156c7393d54e8e39ac6818dea0e7469  tests/S13/test_S13_acceptance.py
7e5650d39efb93f5dea51b5649bf4cb85ad2292ebb133b0ee0d74817de73c9a7  tests/S13/test_S13_hidden.py
0f1fb115adbaa406d3b2bf1bfcaa03b5218fa02a670ba19d09afddbeaa239cf6  tests/S13/trap.patch
39d6f9481356cebdc5112cb5d8eda7638d301d5dccc3af122070d0483de125fb  tests/S14/reference.patch
f0acedd4eee629b39c3e6da880bb886c35e43a9d840c70abe917c2ef84b80762  tests/S14/test_S14_acceptance.py
7ff7b7792165f03df1da03ff940c6d2f60c99e1de07c7d45a37c0d25cc3dd1e0  tests/S14/test_S14_hidden.py
551fe06c3f0eb982e0020131ec9c3a1db3cfd46c7d8c67ebf57070ca425108bf  tests/S14/trap.patch
2c8115dd981a487cb9a23898d2c094d67cfb0698157e843c3bae10b012c9c06f  tests/S15/reference.patch
f1bf60997332688d1abd09127789fdce9c15c32f8935933ef5564cedaf326055  tests/S15/test_S15_acceptance.py
407b1871aa2c2b0ceaeb1d5a2553afe6df355b26849dbb8ab414d62ad088b7ec  tests/S15/test_S15_hidden.py
5d282e4bcca4a373ec681d224d3ab3a85d6994de7aab1280d52a67d430f6edce  tests/S15/trap.patch
ec9371b4999cc0849a80df48e3acaf23ed9703ecb49f47e5495d23f8a09a0e3b  tests/S16/mutants/m1.patch
3f0e38cb8d534544f63fc6d4e638a870eb7f5628e8ac9b7ad6435d8908a02652  tests/S16/mutants/m2.patch
ac46bb070d10acd176862bcf802189186c98ff67f29649bfb2efb913bcd5d154  tests/S16/mutants/m3.patch
08cfab6d5535a8d0d67781c8c03059d97d389e6565657e87edb7efdc63056d9e  tests/S16/mutants/m4.patch
12887f64cdd064c5f87630a49d5bc5ac77faac811f94421e95dc0b68e1eaa29b  tests/S16/reference.patch
952bb11efc1c7845aeb6374bb9adede0cf05a8b9a1d1c982df6bd07cd454e8b1  tests/S16/test_S16_acceptance.py
3210ea06a3cbb3359fd8b03d32311dce4d06feeda5a0e64c9504fd06bb155277  tests/S16/trap.patch
````install/manifest.tsv` には載せず、どの runtime にも配布しない。繰り返し使う運用の道具にする場合は、`scripts/` へ移し、`docs/reports/inventory-elements.tsv` に行を足す。
