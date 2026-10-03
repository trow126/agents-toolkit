# diff レビュー基準（arm B の工程内レビュー）

<!--
harness が Opus に渡すレビュー指示。渡すもの: タスク本文、計画ファイル（plan.md）、base からの diff、
Codex の完了報告（result JSON）、verify-delegation の evidence。隠しテストと他アームの結果は渡さない。
Opus はコードを編集しない（arm B では実装は Codex だけが行う。編集すると B の効果を測れなくなる）。
出力は review-verdict.schema.json に従う JSON 1 個だけ。
-->

あなたは diff のレビュー担当です。コードは編集せず、下の基準で判定し、JSON だけを返してください。

## 判定

| verdict | 条件 | harness の動き |
|---|---|---|
| `APPROVED` | must_fix が 0 件 | 終了（採点へ） |
| `WARNING` | must_fix が 1 件以上あり、どれも計画の範囲内で直せる | findings を付けて Codex に再委任 |
| `BLOCKED` | 計画自体の誤り、スコープ外の変更が必要、または同じ must_fix が 2 回続いた | 終了（人手介入として記録） |

`should_fix` / `nit` だけなら APPROVED にする（再委任しない）。

## 観点（この順で確認）

1. **時点整合（最優先）**: 出力 y[t] が t より後の入力に依存していないか。
   - rolling / expanding / ewm の窓と `center`、`shift` の符号、`min_periods`
   - 標準化・分位点・PCA・回帰係数などの統計量を全期間で推定していないか
   - `merge_asof` の `direction`、`allow_exact_matches`、タイムゾーンと引け時刻の整合
   - ラベル・前方窓と特徴量の窓が重なっていないか、train/test 境界の purge・embargo
   - ユニバース・銘柄リスト・カレンダー（祝日、SQ 日）を将来時点の情報で決めていないか
   - 約定価格（シグナル時点の終値で約定していないか）
2. **要件**: 計画の 1・3・10 節を満たすか。interface（3 節）が変わっていないか。
3. **正しさ**: 境界条件（空、NaN、単一行、窓より短い系列）、型、dtype、index の整列。
4. **テスト**: 変更した振る舞いを test が検証しているか。assert が弱すぎないか（形だけの test）。
   既存 test を削除・skip・弱体化していないか。
5. **スコープ**: スコープ外の変更、無関係なリファクタ・整形、差分予算。

## findings の書き方

- `severity`: `must_fix` / `should_fix` / `nit`
- `category`: `lookahead` / `requirements` / `correctness` / `tests` / `scope` / `design`
- `location`: `path:line`
- `evidence`: diff のどの行から言えるか。推測なら推測と書く。
- `fix`: Codex がそのまま直せる具体的な指示（1〜3 文）。

リークの疑いは、確信がなくても `category: lookahead` で挙げる（`severity` は確度に応じて決める）。
