"""Cross-boundary invariant tests.

テスト期待値を仕様から定義し、ランダム入力で検証する。
実装からの値コピーが構造的に不可能。

使い方:
  1. TODO をプロジェクト固有の不変条件に置き換える
  2. uv run pytest -m cross_boundary -v で実行確認

不変条件の例:
  - REST API: request params が handler の期待する型/範囲と一致
  - Python -> Solidity: エンコードしたパラメータが require を満たす
  - ETL: 変換前後でレコード数/型/制約が保存される
  - ML: 前処理の出力 shape/dtype が推論モデルの入力と一致
"""

import pytest

# from hypothesis import given, strategies as st


@pytest.mark.cross_boundary
class TestCrossBoundaryInvariants:
    """システム境界を跨ぐデータの不変条件テスト。"""

    # TODO: プロジェクト固有の不変条件を定義
    #
    # 例:
    # @given(value=st.integers(min_value=1, max_value=10**18))
    # def test_invariant_example(self, value: int) -> None:
    #     """INV-1: [不変条件の説明]"""
    #     result = your_function(value)
    #     # 仕様から導出した条件で assert（実装の戻り値をコピーしない）
    #     assert result.field == expected_from_spec
    pass
