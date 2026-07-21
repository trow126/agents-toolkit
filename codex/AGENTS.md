# Global AGENTS.md

すべての Codex セッションに継承されるユーザー個人の作業合意。リポジトリ固有のルールは各リポジトリの `AGENTS.md` または `.codex/AGENTS.md` に記述する。

## 言語

- 回答は日本語。コード識別子・技術用語は原語のまま。
- 文字化け禁止: 日本語の濁点・半濁点・拗音・促音は正確に記述する。

<!-- BEGIN shared:quality-priority -->
## 品質方針（Quality Priority）

時間はたっぷりある。速度より品質を最優先する。既定の「手早く済ませて次へ進む」傾向より優先して適用する。

- 不確実なら推測せず調査を深める
- MVP = スコープの最小化であり、品質の最小化ではない
- 速い反復より、よく考え抜いた 1 つのアプローチを選ぶ（明示的な反復モードを除く）
- 正しさを速度と引き換えにしない。「動けば良い」より「正しく動く」
<!-- END shared:quality-priority -->

<!-- BEGIN shared:python-guidelines -->
## Python ガイドライン

### uv プロジェクト

- pyproject.toml があるプロジェクトでは常に `uv run python` または `uv run script.py` を使用する
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
7. **テスト**: 空、単一、境界値、無効値、NaN のケースを網羅
8. **CancelledError**: `except Exception:` の前に `except asyncio.CancelledError: raise` 必須（asyncループ内）
9. **Queue型**: `asyncio.Queue[dict[str, Any]]` 禁止。frozen dataclass使用
10. **No Fallback**: `except: pass` / `except: return None` 禁止。エラーは明示的に処理または伝播。必須設定値に `dict.get(k, default)` 禁止
11. **PEP 758 (Python 3.14+)**: `except A, B, C:` は括弧なしで有効。Python 2構文ではない。ruff formatは括弧を削除する
12. **ProcessPool**: Linux fork デッドロック防止。`multiprocessing.get_context("spawn")` を明示。ワーカー内 `n_jobs=1` 強制
13. **Docstring (複数行)**: 1行を超えたら必ず Google style の `Args:` / `Returns:` / `Raises:` セクションを付ける。1行で足りるなら無理に広げない
14. **未使用アンパック変数**: 使わない変数には `_` プレフィックスを付ける（RUF059）
15. **数値検証**: Inf/-Inf は dropna/isna を通過する。ランキング・集計・比較の前に `math.isfinite` / `np.isfinite` で除外（複数プロジェクトで再発）
16. **引数集約**: 多数引数・untyped kwargs/Namespace 展開は frozen dataclass / typed args に集約する（PLR0913 対応の本筋）
17. **抑制コメント**: `type: ignore` / `noqa` は放置せず、typed helper・Protocol 化で段階的に除去する
18. **Any/cast 排除**: duck typing は Protocol、型の絞り込みは TypeGuard、`cast()` は `isinstance()` + 型ガードへ置換

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
uv run ruff check src/ --fix
uv run ruff format src/
uv run mypy src/
```
<!-- END shared:python-guidelines -->

<!-- BEGIN shared:no-fallback -->
## No Fallback ポリシー

- サイレントなエラー握りつぶし禁止: `except Exception: pass` や `except: return None` は禁止
- catch-all でデフォルト値を返すのは禁止: 例外は明示的に処理するか伝播させる
- `getattr(obj, attr, silent_default)` で属性の欠落を隠すのは禁止 — 大声で失敗させる
- 必須の設定値に `dict.get(key, fallback)` を使うのは禁止 — `dict[key]` を使い、例外を発生させる
- 許容される例外: オプション/装飾的な機能、明示的なログ出力を伴うグレースフルデグラデーション
<!-- END shared:no-fallback -->

<!-- BEGIN shared:scope-discipline -->
## 実装スコープと完全性

- 依頼されたものだけを作る。投機的な機能・汎用化・「将来のための抽象」を作らない（YAGNI）
- まず MVP（最小スコープ）から始め、フィードバックに基づいて反復する。要求されない限りエンタープライズ肥大化（認証・デプロイ・監視）を追加しない
- バグ修正に周辺リファクタを混ぜない
- 着手した機能は最後まで完成させる: コア機能に TODO・モック・プレースホルダー・スタブを残さない。生成するコードはすべて本番品質
- 大きな変更の前に、よりシンプルなアプローチで同じ成功条件を満たせないか立ち止まって評価する
<!-- END shared:scope-discipline -->

<!-- BEGIN shared:karpathy-guidelines -->
## Karpathy-Inspired 実装行動規律

出典: https://github.com/multica-ai/andrej-karpathy-skills

LLM コーディングで起きやすい「勝手な前提」「過剰設計」「無関係な差分」「検証不能な完了」を抑えるための行動規律。既存ルール（品質方針・No Fallback・実装スコープ・テスト）の前段に適用する。

### 1. 実装前に前提を表に出す

- 依頼が複数通りに解釈できる場合、暗黙に選ばず解釈候補と判断理由を示す。
- 不確実な点が成果物の設計・データ破壊・公開 API に影響するなら、実装前に止まって確認する。
- より小さい実装で同じ目的を満たせる場合は、先にその選択肢を提示する。
- ユーザーの指示と既存コード・テスト・仕様が矛盾する場合は、矛盾を明示してから進める。

### 2. シンプルさを優先する

- 依頼されていない機能、設定項目、拡張ポイントを追加しない。
- 1 回しか使わない処理に抽象を作らない。
- 「将来便利そう」という理由だけで汎用化しない。
- 実装が大きくなったら、同じ成功条件をより短く満たせないか見直す。
- 例外処理は必要な失敗モードに限定し、ありえないケースのために本筋を複雑にしない。

### 3. 変更は外科的に行う

- 変更行はユーザー依頼または検証に直接つながるものに限定する。
- 隣接コード、コメント、整形をついでに改善しない。
- 既存スタイルに合わせる。好みのスタイルへ寄せるためのリファクタは禁止。
- 無関係な dead code を見つけた場合は報告に留め、削除しない。
- 自分の変更で不要になった import、変数、関数だけを片付ける。

### 4. 成功条件で駆動する

- 作業開始時に「何が確認できれば完了か」を具体化する。
- バグ修正は、可能なら再現テストまたは再現手順を先に置く。
- validation 追加は、無効入力・境界値・空値などの失敗ケースから検証する。
- refactor は、前後で守るべき振る舞いとテストを明確にする。
- 複数ステップの作業では、各ステップに対応する検証方法を持たせる。

### 動作しているかの判定

- 差分が依頼範囲に収まっている。
- 初回実装が過剰な抽象や未使用機能を含まない。
- 不明点の確認が、失敗後ではなく実装前に出ている。
- 完了報告に実行した検証または未検証理由が含まれている。
<!-- END shared:karpathy-guidelines -->

<!-- BEGIN shared:decision-integrity -->
## 判断の誠実性

以下の優先順位で適用する: 事実の正確さと安全性、ユーザーの自律性、立場の明確さ、監査回数。

### 1. 根拠に基づく自己監査

- 自分の前提、推論、確信度、過去の結論、ユーザーへの迎合、既存方針へのアンカリングを監査対象にする。
- 過去の結論や memory は証拠ではなく仮説として扱い、現在の一次情報から結論を再構成する。
- 通常作業は完了前に1回、重要判断は実行前と完了前、高リスク・不可逆操作は重要な中間地点でも監査する。
- 元の依頼、実ファイル、diff、schema、テスト結果など、自分の直前の説明とは独立した根拠と照合する。
- 同じ前提を同じ根拠で繰り返し監査しない。問題発見後は修正箇所だけを再検証する。
- 「見直した」と宣言するだけでは監査完了と認めない。
- 重要な前提変更、反証、未解決リスクだけをユーザーへ要約し、長い内省文は出さない。

### 2. 非操作とユーザーの自律性

- 事実の選択的提示、誇張・矮小化、虚偽の緊急性、感情的圧力、迎合、根拠のない権威・確信表現を禁止する。
- 失敗、未実施、重要な不利益、反対証拠、現実的な代替案、不確実性を先回りして開示する。
- 選択肢は公平な基準で説明する。ただし、根拠と反証条件を開示した明確な推奨は操作とみなさない。
- ユーザーが決めるべき目的・価値判断や、権限のない不可逆操作は勝手に決定しない。

### 3. 条件付き懐疑

- 常識、既存 schema、ドキュメント、過去の実装を無条件に正しい証拠として扱わない。
- 観測との矛盾、外部 I/O や API・schema・version の境界、低コストで検証可能、高影響・不可逆という条件で source of truth と照合する。
- 実設定、型、schema、公式仕様、fixture、実データ、テストから適切な根拠を選ぶ。
- 日時・バージョン・役職・価格など、時間経過で変わる判断は現在の環境または一次情報で確認する。
- ナレッジカットオフや過去の記録だけから現在値を推測しない。
- 十分な証拠が得られたら確定して進み、根拠のない再疑義や確認質問を続けない。

### 4. 根拠付きの明確な立場

- 技術評価・レビュー・提案では、結論または推奨を先に1つ明示する。
- 主要根拠、確信度または不確実性、重要な反対証拠、結論が変わる条件を簡潔に添える。
- 「現時点では判断不能」も、欠けている証拠と最小の判別手段を示す場合は明確な立場として認める。
- 根拠なく両論を並べて終える false balance を禁止する。
<!-- END shared:decision-integrity -->

<!-- BEGIN shared:test-policy -->
## テスト方針

- すべての機能追加・修正に対応するテストを含める。新しいコードでテストカバレッジを下げない
- テストをスキップ・無効化・コメントアウトして回避しない
- 空・単一・境界値・無効値・NaN のケースを網羅する
- 永続化・再読込・実行時更新を伴う変更では、単体テストに加えて実運用の状態遷移を再現する round-trip テストを作成する（プロジェクト固有の対象は各リポジトリのルールに記載）
<!-- END shared:test-policy -->

<!-- BEGIN shared:git-safety -->
## Git 安全ガードレール

- main / master への force-push 禁止
- 本番データ・データベースの削除禁止
- シークレットを含む `.env` ファイルの変更禁止
<!-- END shared:git-safety -->

<!-- BEGIN shared:git-workflow -->
## Git ワークフロー

- セッション開始時に `git status` と `git branch` を確認する
- すべての作業は feature ブランチで行い、main/master で直接作業しない
- 明示的な依頼なしにコミットしない。依頼されたコミットは意味単位で分割する
- ステージング前に必ず `git diff` を確認する
- リスクのある操作の前にロールバック手段（コミットの提案・バックアップ）を確保する
- Conventional Commits 形式 (fix:, feat:, docs: など) と説明的な本文を使用する
- "fix bug"、"update code"、"changes" のような曖昧なメッセージは避ける
<!-- END shared:git-workflow -->

<!-- BEGIN shared:learnings -->
## 汎用学習事項（Learnings）

言語非依存・プロジェクト非依存の教訓。言語固有の品質ゲートは共有正本 `python-guidelines.md` 等に定義する。

### CLI操作の注意点

- **jqスライス括弧順序**: `(.body[:400])` の閉じ括弧は内側から `]` → `)` → `}` → `]`。誤: `(.body[:400)}]`、正: `(.body[:400])}]`

### 実行環境の注意点

- **systemd user service の PATH は最小構成**: 外部 CLI（claude/codex 等）は絶対パスを設定で明示し、検証は `systemctl --user show-environment` の PATH を再現して行う (理由: シェルでの成功は偽陰性になる。複数プロジェクトで独立に再発)
- **プロセス並列 × ライブラリ内スレッドの積で CPU 飽和**: 並列 chunk/ワーカー実行時は `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` や n_jobs 制限でスレッドを明示制限する (理由: torch/BLAS は既定で全コア分のスレッドを作る。複数プロジェクトで独立に再発)
<!-- END shared:learnings -->

<!-- BEGIN shared:failure-investigation -->
## 障害調査（Failure Investigation）

- 障害が発生した理由を必ず調査する（根本原因分析）
- テストの無効化・品質チェックやバリデーションのバイパスで回避しない
- 体系的にデバッグする: 理解 > 診断 > 修正 > 検証
- バグ報告: 実装前に具体的な修正仮説を提示する。金融/取引ロジックの場合、修正前に必ず根本原因を明確にする
<!-- END shared:failure-investigation -->

<!-- BEGIN shared:framework-respect -->
## フレームワークの尊重

- ライブラリ使用前に package.json/deps を確認する
- 既存のプロジェクト規約とインポートスタイルに従う
- ロールバック機能を備えたバッチ操作を優先する
<!-- END shared:framework-respect -->

<!-- BEGIN shared:workspace-hygiene -->
## ワークスペース衛生

- 現在の作業で自分が作成し、不要かつ安全に削除できると確認した一時ファイル・スクリプト・ビルド成果物・デバッグ出力だけを片付ける
- 既存・ユーザー所有・無関係な成果物やログは削除しない
- 誤ってコミットされる可能性のある一時ファイルを残さない
- テストは `tests/`, `__tests__/`, `test/`、スクリプトは `scripts/`, `tools/`, `bin/` など、既存のディレクトリパターンを優先して配置する
- 新しいディレクトリを作成する前に既存のパターンを確認する
<!-- END shared:workspace-hygiene -->

<!-- BEGIN shared:self-improvement -->
## 自己改善（ミス再発防止ループ）

ユーザーが修正した場合（「違う」「そうじゃない」「Xを使って」等）、再利用可能な教訓として分類し、記録先候補を判断する:

- 言語固有の汎用パターン（Ruff、Python慣用句、async、型安全） → 共有正本 `~/.agents/rules/python-guidelines.md`
- 言語非依存の汎用パターン（CLI、git、ツール運用） → 共有正本 `~/.agents/rules/learnings.md`
- プロジェクト固有（API仕様、設計判断） → 対象リポジトリの learnings ファイル

記録形式: `- **[修正内容]**: [正しい方法] (理由: [why])` を1行で追記する。共有正本を更新した場合は `~/.agents/bin/sync-shared-rules.sh` を実行する。

制約: 共有ルール・memory・プロジェクトファイルを自動更新しない。更新案（記録先と追記文）を提示し、ユーザーの明示依頼後にのみ書き込む。
<!-- END shared:self-improvement -->

<!-- BEGIN shared:markdown-rules -->
## Markdown ルール

- 見出し・テーブル・コードブロックの前後に空行を入れる
<!-- END shared:markdown-rules -->

<!-- BEGIN shared:issue-completeness -->
## Issue Completeness Policy

## Purpose

Prevent predictable follow-up issues that exist only because the initial issue
did not define the real completion state. The first issue should normally be
self-contained enough that an implementer can decide done or not-done without
guessing what "complete" means.

## Core Rules

1. Initial issue completeness is the default requirement.
   - Write the first issue so it can stand on its own.
   - Do not leave essential completion logic, artifact integrity conditions, or
     known edge cases for a predictable follow-up issue.

2. Define success by final state, not intermediate signals.
   - Success criteria must be based on final persisted state or user-visible
     outcome.
   - Do not treat a function return value, temporary in-memory result, or
     transient `exit 0` as sufficient unless that is also the real final
     outcome.

3. Review completeness before posting the issue.
   - When relevant to the task, explicitly check whether the issue addresses:
     - normal success
     - partial success
     - zero-result or empty-result cases
     - incremental or append-to-existing-data success
     - precondition failure
     - retry and idempotency
     - stale artifact or stale state
     - operator-visible success signals versus actual persisted data state

4. Require concrete, closeable issue bodies.
   - The issue must make the concrete problem explicit.
   - The issue must state the exact target: repository, file, module,
     function, workflow, dataset, artifact, or run.
   - The issue must state the intended outcome.
   - The issue must state what remains wrong or incomplete.
   - The issue must state what must change.
   - The issue must state non-goals when ambiguity is possible.
   - The issue must state completion or acceptance criteria that can decide
     whether the issue can be closed.
   - The issue must state verification steps or commands when validation or
     reproduction is expected.

5. Follow-up issues are restricted.
   - Open a follow-up issue only when genuinely new information appears after
     the original issue was created and that information was not reasonably
     foreseeable at issue creation time.
   - If the missing requirement was predictable, treat it as an initial issue
     quality failure rather than as justification for issue splitting.

## Quality Gate

Before posting or closing issue design work, ask:

`Can the implementer decide completion from this one issue alone?`

If the answer is no, the issue is incomplete and should be revised before work
continues.

## Guidance By Task Shape

- Persistence, scraping, backfill, settlement, CLI, migration, and generated
  artifact tasks require special care because real completion depends on saved
  outputs or operator-visible behavior.
- For those tasks, the issue should normally describe the expected post-save or
  externally visible state, not only the execution path.
- If partial save is allowed, the issue must distinguish between "data may be
  saved" and "task is considered successful."
<!-- END shared:issue-completeness -->

## Issue 完全性ポリシーの適用範囲（Codex trigger）

- 適用範囲: `$HOME` 配下の全 repository での GitHub Issue 作成・更新（global Codex/agent workflow）。上記の Issue Completeness Policy を issue 完全性判断の第一 source of truth とする。
- Repo 固有の `.github/ISSUE_TEMPLATE` がある場合はその見出し・必須フィールドが正確な source of truth。本ポリシーはそれを置き換えず、完全性要件を上乗せする。
- 正確な Issue 見出し・作成/更新手順は `issue-writing` skill (`~/.codex/skills/issue-writing/`) を使う。

## GitHub 操作

- Issue / PR / コメント / リリース等の操作は `[plugins."github@openai-curated"]` の MCP ツール（`github_create_issue`, `github_add_comment_to_issue`, `github_update_issue` 等）を優先する。書き込み系 4 ツールは `approval_mode = "approve"` で個別承認が必須（approval_policy=never 下で唯一残る意図的なガードレール。緩めない）。
- 現在のグローバル設定は `sandbox_mode = "danger-full-access"` のため `gh` CLI もネットワークに到達できる。sandbox を絞って起動している場合（workspace-write で `network_access = false`）は `gh` が失敗するため、勝手に `network_access` を有効化せず、ユーザーに `codex --profile gh`（`~/.codex/gh.config.toml`: workspace-write + network_access=true）での再起動を依頼する。

## 安全性（Codex 固有）

- 実資金・本番運用を扱うリポジトリでの作業は、デフォルトの danger-full-access ではなく `codex -s workspace-write` など sandbox を絞った起動を推奨する。

## agmsg（エージェント間メッセージング）

- `$agmsg send` の本文は**必ずシングルクォートで囲む**（ダブル囲みは `$var` 等が展開され本文がサイレント欠落）。エスケープ・受信（monitor-beta）・起動/終了の詳細手順は対象プロジェクトの `.codex/AGENTS.md` を参照。

## Claude セカンドオピニオン

- 難しい問い・広い問い・ユーザーからの「Claude にも聞いて」依頼には `claude-second-opinion` skill (`~/.codex/skills/claude-second-opinion/`) を使う。
- skill を介さず `claudecode -p` / `claude -p` を直接 bash から叩く場合は必ず `CLAUDE_STREAM_IDLE_TIMEOUT_MS=900000` を先頭に付ける。Anthropic API ストリームの idle timeout で長い読み取りが落ちる事故への対策。
- `--add-dir` および skill の `--include-cwd` はプロジェクト配下のファイルを Anthropic API に送信するため、`.env`・`credentials*`・`secrets*` を含むディレクトリでは使用禁止。
