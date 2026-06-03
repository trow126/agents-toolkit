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

## クイックコマンド
```bash
uv run ruff check src/ --fix
uv run ruff format src/
uv run mypy src/
```
