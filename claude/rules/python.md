---
paths:
  - "**/*.py"
---

# Python ルール

## uv プロジェクト
- pyproject.toml があるプロジェクトでは常に `uv run python` または `uv run script.py` を使用する
- `python` や `python3` を直接使用しない
- すべてに適用: アドホックスクリプト、デバッグ、テスト、一時的な実行
- 一時確認の Python 実行で `__pycache__` を残したくない場合は `PYTHONDONTWRITEBYTECODE=1` を付ける
- `__pycache__` cleanup のために `rm -rf` を実行しない

## 実装前チェックリスト

1. **`__all__`**: アルファベット順にソート（RUF022）
2. **ロギング**: f-stringではなく `%s` フォーマットを使用（G004）
3. **例外**: `logger.exception("msg")` に `{e}` を含めない（TRY401）
4. **型ヒント**: `__init__` に `-> None` を付与（ANN204）
5. **日時**: `datetime.now(timezone.utc)` を使用（DTZ005）
6. **非同期**: while/sleepを避け、Eventを使用（ASYNC110）
7. **テスト**: 空、単一、境界値、無効値、NaN のケースを網羅
8. **CancelledError**: `except Exception:` の前に `except asyncio.CancelledError: raise` 必須（asyncループ内）
9. **Queue型**: `asyncio.Queue[dict[str, Any]]` 禁止。frozen dataclass使用
10. **No Fallback**: `except: pass` / `except: return None` 禁止。エラーは明示的に処理または伝播。必須設定値に `dict.get(k, default)` 禁止
11. **PEP 758 (Python 3.14+)**: `except A, B, C:` は括弧なしで有効。Python 2構文ではない。ruff formatは括弧を削除する
12. **ProcessPool**: Linux fork デッドロック防止。`multiprocessing.get_context("spawn")` を明示。ワーカー内 `n_jobs=1` 強制
13. **Docstring (複数行)**: 1行を超えたら必ず Google style の `Args:` / `Returns:` / `Raises:` セクションを付ける。1行で足りるなら無理に広げない
14. **未使用アンパック変数**: 使わない変数には `_` プレフィックスを付ける（RUF059）

## 主要な型安全ガード

```python
# ゼロ除算
rate = wins / total if total > 0 else 0.0

# インデックス境界
first = items[0] if items else None

# 空のDataFrame
if df.empty or df["col"].isna().all():
    return None

# MIN_CELLS パターン（テーブルパース）
MIN_CELLS = max_index + 1
if len(cells) < MIN_CELLS:
    return None
```

## クイックコマンド
```bash
# 各コマンドは個別に実行（&& はパーミッションチェックをバイパスする: Issue #16180）
uv run ruff check src/ --fix
uv run ruff format src/
uv run mypy src/
```
