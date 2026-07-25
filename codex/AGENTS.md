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

## Python

Python の実装・修正・レビュー時は、必要時に `~/.codex/references/python-quality.md` を読み、その品質ゲート（uv 実行規約・Ruff チェックリスト・型安全ガード）を適用する。常時ロードしない。

<!-- BEGIN shared:no-fallback -->
## No Fallback ポリシー

- サイレントなエラー握りつぶし禁止: `except Exception: pass` や `except: return None` は禁止
- catch-all でデフォルト値を返すのは禁止: 例外は明示的に処理するか伝播させる
- `getattr(obj, attr, silent_default)` で属性の欠落を隠すのは禁止 — 大声で失敗させる
- 必須の設定値に `dict.get(key, fallback)` を使うのは禁止 — `dict[key]` を使い、例外を発生させる
- 許容される例外: オプション/装飾的な機能、明示的なログ出力を伴うグレースフルデグラデーション
<!-- END shared:no-fallback -->

<!-- BEGIN shared:karpathy-guidelines -->
## Karpathy-Inspired 実装行動規律

出典: https://github.com/multica-ai/andrej-karpathy-skills

LLM コーディングで起きやすい「勝手な前提」「過剰設計」「無関係な差分」「検証不能な完了」を抑える 4 原則。既存ルール（品質方針・No Fallback・テスト）の前段に適用する。細部は各原則の意図に照らして自分で判断する。

1. **前提を表に出す**: 依頼が複数に解釈できる、または不確実さが設計・データ・公開 API に波及するなら、暗黙に選ばず実装前に解釈と判断理由を示す。指示と既存コード・仕様の矛盾も同様に明示してから進める。
2. **シンプルさを優先する**: 依頼されていない機能・抽象・汎用化を足さない。MVP = スコープの最小化であり品質の最小化ではない。着手したコア機能は TODO・スタブを残さず完成させる。
3. **変更は外科的に行う**: 差分は依頼と検証に直接つながる行に限定し、既存のスタイル・規約・依存に従う。ついで改善や周辺リファクタを混ぜず、無関係な問題は報告に留める。
4. **成功条件で駆動する**: 着手前に「何が確認できれば完了か」を具体化し（バグ修正なら再現を先に）、完了報告には実行した検証または未検証の理由を含める。
<!-- END shared:karpathy-guidelines -->

<!-- BEGIN shared:decision-integrity -->
## 判断の誠実性

優先順位: 事実の正確さと安全性 > ユーザーの自律性 > 立場の明確さ > 監査回数。

1. **根拠に基づく自己監査**: 重要判断・不可逆操作の前と完了前に、自分の前提・過去の結論・迎合を、直前の自分の説明とは独立した一次情報（実ファイル・diff・テスト結果）と照合する。「見直した」という宣言だけを監査と認めない。ユーザーへは重要な前提変更・反証・未解決リスクだけを要約する。
2. **非操作と自律性**: 選択的提示・誇張・虚偽の緊急性・迎合・根拠のない確信表現を使わない。失敗・不利益・反対証拠・代替案を先回りして開示する。根拠と反証条件を示した明確な推奨は操作ではない。ユーザーが決めるべき価値判断と権限のない不可逆操作は勝手に決めない。
3. **条件付き懐疑**: 既存の schema・ドキュメント・過去の結論・memory は証拠ではなく仮説として扱い、高影響または低コストで検証可能なら source of truth（実設定・公式仕様・実データ）と照合する。時間経過で変わる値はカットオフ知識から推測せず現在の一次情報で確認する。十分な証拠が得られたら確定して進む。
4. **根拠付きの明確な立場**: 評価・レビュー・提案では結論を 1 つ先に示し、主要根拠・確信度・結論が変わる条件を添える。根拠なき両論併記で終えない。「判断不能」も欠けている証拠と最小の判別手段を示せば明確な立場である。
<!-- END shared:decision-integrity -->

<!-- BEGIN shared:test-policy -->
## テスト方針

- すべての機能追加・修正に対応するテストを含める。新しいコードでテストカバレッジを下げない
- テストをスキップ・無効化・コメントアウトして回避しない
- 空・単一・境界値・無効値・NaN のケースを網羅する
- 永続化・再読込・実行時更新を伴う変更では、単体テストに加えて実運用の状態遷移を再現する round-trip テストを作成する（プロジェクト固有の対象は各リポジトリのルールに記載）
<!-- END shared:test-policy -->

<!-- BEGIN shared:git-workflow -->
## Git ワークフロー

- 安全ガードレール: main/master への force-push 禁止。本番データ・データベースの削除禁止。シークレットを含む `.env` ファイルの変更禁止
- セッション開始時に `git status` と `git branch` を確認する
- すべての作業は feature ブランチで行い、main/master で直接作業しない
- 明示的な依頼なしにコミットしない。依頼されたコミットは意味単位で分割する
- ステージング前に必ず `git diff` を確認する
- リスクのある操作の前にロールバック手段（コミットの提案・バックアップ）を確保する
- Conventional Commits 形式 (fix:, feat:, docs: など) と説明的な本文を使用する
- "fix bug"、"update code"、"changes" のような曖昧なメッセージは避ける
<!-- END shared:git-workflow -->

## 汎用学習事項（Learnings）

- 環境・CLI 系の再発バグ（systemd PATH・スレッド飽和・jq quoting 等）に触れる作業でのみ `~/.agents/rules/learnings.md` を読む（常時ロードしない）。記録の追加は自己改善ルールの承認境界に従う。

<!-- BEGIN shared:failure-investigation -->
## 障害調査（Failure Investigation）

- 障害が発生した理由を必ず調査する（根本原因分析）
- 体系的にデバッグする: 理解 > 診断 > 修正 > 検証
- バグ報告: 実装前に具体的な修正仮説を提示する。金融/取引ロジックの場合、修正前に必ず根本原因を明確にする
<!-- END shared:failure-investigation -->

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

## GitHub Issue 作成・更新

- Issue の作成・更新（`$HOME` 配下の全 repository）は `issue-writing` skill（`~/.agents/skills/issue-writing/`）を使う。Issue Completeness Policy（完全性要件の第一 source of truth）は同 skill に内包。repo 固有の `.github/ISSUE_TEMPLATE` がある場合はその見出し・必須フィールドが正確な source of truth で、本ポリシーは完全性要件を上乗せする。

## GitHub 操作

- Issue / PR / コメント / リリース等の操作は `[plugins."github@openai-curated"]` の MCP ツール（`github_create_issue`, `github_add_comment_to_issue`, `github_update_issue` 等）を優先する。書き込み系 4 ツールは `approval_mode = "approve"` で個別承認が必須（approval_policy=never 下で唯一残る意図的なガードレール。緩めない）。
- 現在のグローバル設定は `sandbox_mode = "danger-full-access"` のため `gh` CLI もネットワークに到達できる。sandbox を絞って起動している場合（workspace-write で `network_access = false`）は `gh` が失敗するため、勝手に `network_access` を有効化せず、ユーザーに `codex --profile gh`（`~/.codex/gh.config.toml`: workspace-write + network_access=true）での再起動を依頼する。

## 安全性（Codex 固有）

- 実資金・本番運用を扱うリポジトリでの作業は、デフォルトの danger-full-access ではなく `codex -s workspace-write` など sandbox を絞った起動を推奨する。

## agmsg（エージェント間メッセージング）

- `$agmsg send` の本文は**必ずシングルクォートで囲む**（ダブル囲みは `$var` 等が展開され本文がサイレント欠落）。エスケープ・受信（monitor-beta）・起動/終了の詳細手順は対象プロジェクトの `.codex/AGENTS.md` を参照。

## Claude セカンドオピニオン

- 難しい問い・広い問い・ユーザーからの「Claude にも聞いて」依頼には `claude-second-opinion` skill (`~/.agents/skills/claude-second-opinion/`) を使う。
- skill を介さず `claudecode -p` / `claude -p` を直接 bash から叩く場合は必ず `CLAUDE_STREAM_IDLE_TIMEOUT_MS=900000` を先頭に付ける。Anthropic API ストリームの idle timeout で長い読み取りが落ちる事故への対策。
- `--add-dir` および skill の `--include-cwd` はプロジェクト配下のファイルを Anthropic API に送信するため、`.env`・`credentials*`・`secrets*` を含むディレクトリでは使用禁止。
