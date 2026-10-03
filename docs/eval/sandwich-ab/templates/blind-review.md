# 盲検 review の採点基準（アーム間の品質比較）

<!--
アームの結果を比べるための事後採点。arm B の工程内レビュー（review.md）とは別物で、別の reviewer セッションが行う。
harness（sandwich_ab.py blind-pack）が題材ごとに候補 diff をランダムな記号（A, B, C, …）に置き換え、並び順を変えた 2 組を作る。
reviewer には アーム名・モデル名・所要時間・トークン・Codex の報告・計画ファイル・レビュー履歴を渡さない。
渡すもの: タスク本文、scope、各候補の最終 diff（src と tests のみ。harness が生成物・lockfile・.agents-toolkit を除く）。
-->

あなたは盲検の reviewer です。候補の作り手は分かりません。各候補を独立に、下の 5 軸で 0〜5 点で採点し、順位を付けてください。

## 軸

| 軸 | 5 点 | 0 点 |
|---|---|---|
| requirements | タスク本文の要件と interface をすべて満たす | 主要な要件を満たさない |
| correctness | 不具合・回帰のリスクが見当たらない | 明確な不具合がある |
| leakage | 出力が時点 t より後の情報に依存しない（時系列を扱わない題材は 5） | 明確な lookahead がある |
| tests | 変更した振る舞いを、境界条件を含めて検証している | test が無いか、形だけ |
| design | 既存の構造・命名・流儀に合い、余計な変更が無い | 構造を壊す、無関係な変更が多い |

## 出力（JSON のみ）

```json
{
  "task": "S01",
  "set": "v1",
  "scores": {
    "A": {"requirements": 0, "correctness": 0, "leakage": 0, "tests": 0, "design": 0,
          "defects": ["path:line 説明"], "leak_findings": ["path:line 説明"]}
  },
  "ranking": ["A", "B"]
}
```

## 注意

- 文体（コメントの多さ、命名の癖）でモデルを推測しようとしない。推測できても採点に使わない。
- `defects` には回帰・不具合だけを書く。好みの問題は書かない。
- leakage の判断に使った行を `leak_findings` に必ず書く（無ければ空配列）。
