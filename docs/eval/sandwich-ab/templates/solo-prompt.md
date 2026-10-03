次のタスクを、このリポジトリで実装してください。

# {title}

{body}

## interface（変更しないこと）

{interface}

## 制約

- 変更してよいパス（gitignore 形式）:
{scope_paths}
- 差分予算: {diff_budget_files} files / {diff_budget_lines} 行（追加+削除、新規ファイルを含む）
- 依存・lockfile の変更は不可。docs・README・設定ファイルは変更しない。
- 依頼されていないリファクタ・整形をしない。既存の test を削除・skip・弱体化しない。
- commit・push・PR 作成・外部サービスへの書き込みをしない。
- 終える前に次の check を実行し、失敗したら scope の中で直して再実行する:
{required_checks}
- 判断に迷う点は妥当な仮定で進め、最後に仮定を列挙する。

最後に、変更したファイル、実行した check とその結果、置いた仮定を短く報告してください。
