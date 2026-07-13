## 汎用学習事項（Learnings）

言語非依存・プロジェクト非依存の教訓。言語固有の品質ゲートは共有正本 `python-guidelines.md` 等に定義する。

### CLI操作の注意点

- **jqスライス括弧順序**: `(.body[:400])` の閉じ括弧は内側から `]` → `)` → `}` → `]`。誤: `(.body[:400)}]`、正: `(.body[:400])}]`

### 実行環境の注意点

- **systemd user service の PATH は最小構成**: 外部 CLI（claude/codex 等）は絶対パスを設定で明示し、検証は `systemctl --user show-environment` の PATH を再現して行う (理由: シェルでの成功は偽陰性になる。複数プロジェクトで独立に再発)
- **プロセス並列 × ライブラリ内スレッドの積で CPU 飽和**: 並列 chunk/ワーカー実行時は `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` や n_jobs 制限でスレッドを明示制限する (理由: torch/BLAS は既定で全コア分のスレッドを作る。複数プロジェクトで独立に再発)
