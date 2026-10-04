# Causality (leak) tests

Use these for every function whose output at row `t` must not depend on input after `t`: features, signals, labels with a declared horizon, rolling statistics, resampling, and anything a backtest consumes. They come from the leak-detection tests of the 2026-10 A/B experiments in agents-toolkit (`docs/eval/sandwich-ab/templates/hidden_test_example.py`), where reviewers reading the diff missed every leak these tests caught.

## The three tests

1. **Prefix invariance**: `f(x[:k])` equals `f(x)[:k]` for several `k`. Output `t` does not depend on input after `t`.
2. **Future perturbation**: replace the input after a cut with large values unrelated to the original. Output before the cut is unchanged. For a label with a forward window of `horizon` rows, compare only rows before `cut − horizon`.
3. **Sensitivity**: change the input at one row before the cut. Output from that row on changes. Without this test, an implementation that returns all NaN passes tests 1 and 2.

Compare exactly (`check_exact=True`): floating-point tolerance can hide a small leak. Use several cuts, including one near the start (warm-up) and one near the end. Use synthetic data with a fixed seed, so that the tests do not depend on files outside the repository.

## Helpers (pandas)

Adapt names and columns to the repository; keep the helpers in the test module or a test utility module.

```python
from collections.abc import Callable

import numpy as np
import pandas as pd


def perturb_after(frame: pd.DataFrame, cut: int, cols: list[str], *, seed: int = 0, scale: float = 1e3) -> pd.DataFrame:
    """Copy of frame with cols from row cut on replaced by large values unrelated to the originals."""
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
    base = fn(frame)
    moved = fn(perturb_after(frame, cut, cols))
    upto = cut - horizon
    pd.testing.assert_frame_equal(base.iloc[:upto], moved.iloc[:upto], check_exact=True)


def assert_sensitive(fn, frame, row: int, cols: list[str]) -> None:
    moved = frame.copy()
    for c in cols:
        moved.loc[moved.index[row], c] = moved[c].iloc[row] * 1.5 + 1.0
    a, b = fn(frame).iloc[row:], fn(moved).iloc[row:]
    assert not a.equals(b), "output does not react to its input (all-NaN or constant implementation?)"


# def test_no_lookahead():
#     ticks = make_synthetic_ticks(n=500, seed=1)
#     fn = lambda f: compute_feature(f, window=20)
#     assert_prefix_invariant(fn, ticks, cuts=[50, 137, 499])
#     assert_future_perturbation_invariant(fn, ticks, cut=300, cols=["bid", "ask"])
#     assert_sensitive(fn, ticks, row=250, cols=["bid", "ask"])
```

For a function returning a Series, wrap it (`lambda f: fn(f).to_frame()`). For non-pandas code, apply the same three properties to arrays or records.

## What the tests do not cover

- Leaks through fitted state (a scaler or model fitted on the whole sample): test that fitting on rows before the cut and on all rows gives the same output before the cut.
- Leaks through data joins (as-of joins, revised data): test with a fixture whose later revision differs from the first release.
- Train/test splits: test that no test-period timestamp appears in training input.
