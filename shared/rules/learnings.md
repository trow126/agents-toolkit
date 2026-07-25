## 汎用学習事項（Learnings）

言語非依存・プロジェクト非依存の教訓。言語固有の品質ゲートは共有正本 `python-guidelines.md` 等に定義する。

### CLI操作の注意点

- **jqスライス括弧順序**: `(.body[:400])` の閉じ括弧は内側から `]` → `)` → `}` → `]`。誤: `(.body[:400)}]`、正: `(.body[:400])}]`

### エージェント設定の注意点

- **共有ルールの原則ベース圧縮は Claude 5 世代基準**: karpathy-guidelines / decision-integrity は 2026-07 に細則列挙型から原則ベースへ圧縮した（理由: Claude 5 の context engineering 新ルール「細則よりモデルの判断に任せる」への準拠と常時注入削減）。共有正本は Codex も消費するため、Codex 側で遵守低下を観測したら Codex 専用の補足を `codex/` 側に足す（正本を再肥大化させない）

### 実行環境の注意点

- **systemd user service の PATH は最小構成**: 外部 CLI（claude/codex 等）は絶対パスを設定で明示し、検証は `systemctl --user show-environment` の PATH を再現して行う (理由: シェルでの成功は偽陰性になる。複数プロジェクトで独立に再発)
- **プロセス並列 × ライブラリ内スレッドの積で CPU 飽和**: 並列 chunk/ワーカー実行時は `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` や n_jobs 制限でスレッドを明示制限する (理由: torch/BLAS は既定で全コア分のスレッドを作る。複数プロジェクトで独立に再発)
