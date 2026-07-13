## No Fallback ポリシー

- サイレントなエラー握りつぶし禁止: `except Exception: pass` や `except: return None` は禁止
- catch-all でデフォルト値を返すのは禁止: 例外は明示的に処理するか伝播させる
- `getattr(obj, attr, silent_default)` で属性の欠落を隠すのは禁止 — 大声で失敗させる
- 必須の設定値に `dict.get(key, fallback)` を使うのは禁止 — `dict[key]` を使い、例外を発生させる
- 許容される例外: オプション/装飾的な機能、明示的なログ出力を伴うグレースフルデグラデーション
