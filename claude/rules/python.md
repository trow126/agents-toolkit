---
paths:
  - "**/*.py"
---

<!-- 正本: ~/.agents/rules/python-guidelines.md（編集は正本側で行い、~/.agents/bin/sync-shared-rules.sh で同期する） -->
<!-- BEGIN shared:python-guidelines -->
## Python ガイドライン

### uv プロジェクト

- pyproject.toml があるプロジェクトでは常に `uv run python` または `uv run script.py` を使用する
- **Claude Code の sandbox 内では素の `uv` ではなく `~/.claude/bin/uvw` を経由する**（uv の既定 cache/data path が sandbox の write 境界外・denyRead 下にあり起動前に失敗するため。uvw は可変 state を session temp へ固定する。Codex や CI 等 sandbox 外の実行はこの限りではない）
- `python` / `python3` を直接実行するのは、システム Python 自体の確認など明示的な理由がある場合のみ（理由を述べる）
- `uv` 未導入または非 uv プロジェクトでは、まず環境を確認し、推測で bare `python` にフォールバックしない
- 一時確認の Python 実行で `__pycache__` を残したくない場合は `PYTHONDONTWRITEBYTECODE=1` を付ける
- `__pycache__` cleanup のために `rm -rf` を実行しない

### 実装前チェックリスト

1. **`__all__`**: アルファベット順にソート（RUF022）
2. **ロギング**: f-stringではなく `%s` フォーマットを使用（G004）
3. **例外**: `logger.exception("msg")` に `{e}` を含めない（TRY401）
4. **型ヒント**: `__init__` に `-> None` を付与（ANN204）
5. **日時**: `datetime.now(timezone.utc)` を使用（DTZ005）
6. **非同期**: while/sleepを避け、Eventを使用（ASYNC110）
7. **CancelledError**: `except Exception:` の前に `except asyncio.CancelledError: raise` 必須（asyncループ内）
8. **Queue型**: `asyncio.Queue[dict[str, Any]]` 禁止。frozen dataclass使用
9. **PEP 758 (Python 3.14+)**: `except A, B, C:` は括弧なしで有効。Python 2構文ではない。ruff formatは括弧を削除する
10. **ProcessPool**: Linux fork デッドロック防止。`multiprocessing.get_context("spawn")` を明示。ワーカー内 `n_jobs=1` 強制
11. **Docstring (複数行)**: 1行を超えたら必ず Google style の `Args:` / `Returns:` / `Raises:` セクションを付ける。1行で足りるなら無理に広げない
12. **未使用アンパック変数**: 使わない変数には `_` プレフィックスを付ける（RUF059）
13. **数値検証**: Inf/-Inf は dropna/isna を通過する。ランキング・集計・比較の前に `math.isfinite` / `np.isfinite` で除外（複数プロジェクトで再発）
14. **引数集約**: 多数引数・untyped kwargs/Namespace 展開は frozen dataclass / typed args に集約する（PLR0913 対応の本筋）
15. **抑制コメント**: `type: ignore` / `noqa` は放置せず、typed helper・Protocol 化で段階的に除去する
16. **Any/cast 排除**: duck typing は Protocol、型の絞り込みは TypeGuard、`cast()` は `isinstance()` + 型ガードへ置換

### 主要な型安全ガード

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

### クイックコマンド

```bash
# Claude Code sandbox 内では uv を ~/.claude/bin/uvw に読み替える
uv run ruff check src/ --fix
uv run ruff format src/
uv run mypy src/
```
<!-- END shared:python-guidelines -->

## Claude Code 固有

- クイックコマンドは可読性・ログ・失敗箇所の分離のため個別実行を既定とし、複合 command chain は必要時だけ使う
