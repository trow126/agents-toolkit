---
paths:
  - "**/*.py"
---

<!-- 正本: ~/.agents/rules/python-guidelines.md（編集は正本側で行い、~/.agents/bin/sync-shared-rules.sh で同期する） -->
<!-- BEGIN shared:python-guidelines -->
## Python ガイドライン

### 実行環境

- pyproject.toml があるプロジェクトでは `uv run` を既定とする。bare `python` / `python3` はシステム Python 自体の確認など明示的な理由がある場合のみ使い、`uv` 未導入・非 uv プロジェクトではまず環境を確認し、推測でフォールバックしない
- uv の可変 state を一時領域へ分離したい場合は `~/.claude/bin/uvw` を使う。現行 owner policy は sandbox 無効のため、素の `uv` も使用できる
- 一時確認の実行では `PYTHONDONTWRITEBYTECODE=1` で `__pycache__` を残さない。`__pycache__` cleanup のために `rm -rf` を実行しない

### 品質原則

- ruff / mypy を通る形で書くことを既定とし、細目（import 順・logging 書式・型注釈・timezone aware datetime 等）は linter の指摘に従って解消する。抑制コメント（`type: ignore` / `noqa`）・`Any`・`cast()` は放置せず、Protocol・TypeGuard・typed helper で段階的に除去する
- エラーを silent fallback で隠さない: `except: pass`・catch-all でのデフォルト値返却・必須設定への `dict.get(key, fallback)` は使わず、例外は明示的に処理するか伝播させて fail loudly にする。許容はオプション/装飾的な機能の、明示的なログ出力を伴う graceful degradation のみ
- 境界値は事前判定で守る: ゼロ除算・空コレクション・空 DataFrame を先に判定する。Inf/-Inf は dropna/isna を通過するため、ランキング・集計・比較の前に `math.isfinite` / `np.isfinite` で除外する（複数プロジェクトで再発）
- 多数引数・untyped kwargs/Namespace 展開は frozen dataclass / typed args に集約する。docstring は 1 行を超えたら Google style の `Args:` / `Returns:` / `Raises:` を付ける

### 非同期・並行の footgun

- async ループでは `except Exception:` の前に `except asyncio.CancelledError: raise` を置く。ポーリングの while/sleep より Event を使う
- ProcessPool は Linux fork デッドロック防止のため `multiprocessing.get_context("spawn")` を明示し、ワーカー内は `n_jobs=1` に制限する
- PEP 758 (Python 3.14+): `except A, B, C:` は括弧なしで有効な現行構文であり Python 2 構文ではない。ruff format は括弧を削除する

### クイックコマンド

```bash
# state を一時領域へ分離する場合は uv を ~/.claude/bin/uvw に読み替える
uv run ruff check src/ --fix
uv run ruff format src/
uv run mypy src/
```
<!-- END shared:python-guidelines -->

## Claude Code 固有

- クイックコマンドは可読性・ログ・失敗箇所の分離のため個別実行を既定とし、複合 command chain は必要時だけ使う
