"""隠しテストの書き方の例（リーク検出用の perturbation test）。

題材ごとの隠しテストは private overlay（tests/S*/）に置き、採点時だけ作業ツリーの写しの tests/_hidden/ へ写す。
どのアームにも見せない。ここにあるのは汎用の型だけで、特定の repo の関数名は書かない。

型は 3 つ:
1. 接頭辞不変性: f(x[:k]) と f(x)[:k] が一致する（出力 y[t] が t より後の入力に依存しない）。
2. 未来の摂動: cut より後の入力を大きく書き換えても、cut より前の出力が一致する。
3. 感度（空振り防止）: cut より前の入力を書き換えると、出力が実際に変わる。
   これが無いと「常に NaN を返す実装」も 1・2 を通ってしまう。

この 3 つを、題材ごとの関数に合わせて組み合わせる。比較は check_exact=True（浮動小数の丸めで逃がさない）。
"""
from __future__ import annotations

from collections.abc import Callable

import numpy as np
import pandas as pd


def perturb_after(frame: pd.DataFrame, cut: int, cols: list[str], *, seed: int = 0, scale: float = 1e3) -> pd.DataFrame:
    """cut 行目以降の cols を、元の値と無関係な大きな値で置き換えた写しを返す。"""
    rng = np.random.default_rng(seed)
    out = frame.copy()
    n = len(out) - cut
    for c in cols:
        out.loc[out.index[cut:], c] = out[c].iloc[:cut].abs().mean() * scale * (1 + rng.random(n))
    return out


def assert_prefix_invariant(fn: Callable[[pd.DataFrame], pd.DataFrame], frame: pd.DataFrame, cuts: list[int]) -> None:
    full = fn(frame)
    for k in cuts:
        pd.testing.assert_frame_equal(fn(frame.iloc[:k]).reset_index(drop=True),
                                      full.iloc[:k].reset_index(drop=True), check_exact=True)


def assert_future_perturbation_invariant(fn, frame, cut, cols, *, horizon: int = 0) -> None:
    """horizon > 0 のラベル関数では、cut − horizon より前の行だけを比べる（前方窓の正当な依存を除く）。"""
    base = fn(frame)
    moved = fn(perturb_after(frame, cut, cols))
    upto = cut - horizon
    pd.testing.assert_frame_equal(base.iloc[:upto], moved.iloc[:upto], check_exact=True)


def assert_sensitive(fn, frame, row: int, cols: list[str]) -> None:
    """row 行目の入力を変えると、row 以降の出力のどこかが変わる（空振り防止）。"""
    moved = frame.copy()
    for c in cols:
        moved.loc[moved.index[row], c] = moved[c].iloc[row] * 1.5 + 1.0
    a, b = fn(frame).iloc[row:], fn(moved).iloc[row:]
    assert not a.equals(b), "入力を変えても出力が変わらない（常に NaN 等の空振り実装の疑い）"


# 使用例（題材の関数に置き換える）:
# def test_hidden_no_lookahead():
#     ticks = make_synthetic_ticks(n=500, seed=1)
#     fn = lambda f: compute_something(f, window=20)
#     assert_prefix_invariant(fn, ticks, cuts=[50, 137, 499])
#     assert_future_perturbation_invariant(fn, ticks, cut=300, cols=["bid", "ask"])
#     assert_sensitive(fn, ticks, row=250, cols=["bid", "ask"])
