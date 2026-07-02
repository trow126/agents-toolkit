---
name: sc:research
description: 深い Web リサーチを自動計画とインテリジェントな検索で行う
---

# /sc:research - 深層リサーチコマンド

> **Context Framework Note**: 適応的計画、マルチホップ推論、エビデンスベースの統合による包括的リサーチ機能を有効化するコマンド。

## Triggers
- ナレッジカットオフを超えたリサーチ質問
- 複雑なリサーチ質問
- 時事・リアルタイム情報
- 学術的・技術的リサーチ要件
- 市場分析・競合インテリジェンス

## Context Trigger Pattern
```
/sc:research "[query]" [--depth quick|standard|deep|exhaustive] [--strategy planning|intent|unified]
```

## Behavioral Flow

### 1. Understand（理解）(5-10% effort)
- クエリの複雑さと曖昧さを評価
- 必要な情報タイプを特定
- リソース要件を決定
- 成功基準を定義

### 2. Plan（計画）(10-15% effort)
- 複雑さに基づいて計画戦略を選択
- 並列化の機会を特定
- リサーチ質問を分解
- 調査マイルストーンを作成

### 3. TaskCreate（タスク作成）(5% effort)
- 適応的タスク階層を作成
- クエリの複雑さに応じてタスクをスケーリング（3-15タスク）
- タスク依存関係を確立
- 進捗追跡を設定

### 4. Execute（実行）(50-60% effort)
- **並列優先検索**: 類似クエリは常にバッチ処理
- **スマート抽出**: コンテンツの複雑さに応じてルーティング
- **マルチホップ探索**: エンティティとコンセプトチェーンを追跡
- **エビデンス収集**: ソースと信頼度を追跡

### 5. Track（追跡）(継続的)
- TaskCreate の進捗をモニタリング
- 信頼度スコアを更新
- 成功パターンを記録
- 情報ギャップを特定

### 6. Validate（検証）(10-15% effort)
- エビデンスチェーンを検証
- ソースの信頼性を確認
- 矛盾を解決
- 完全性を確保

## Key Patterns

### 並列実行
- すべての独立検索をバッチ処理
- 並行抽出を実行
- 依存関係がある場合のみ逐次処理

### エビデンス管理
- 検索結果を追跡
- 利用可能な場合は明確な引用を提供
- 不確実性を明示的に記録

### 適応的深度
- **Quick**: 基本検索、1ホップ、サマリー出力
- **Standard**: 拡張検索、2-3ホップ、構造化レポート
- **Deep**: 包括的検索、3-4ホップ、詳細分析
- **Exhaustive**: 最大深度、5ホップ、完全調査

## MCP Integration
- **Tavily**: プライマリ検索・抽出エンジン
- **Sequential**: 複雑な推論と統合
- **Playwright**: JavaScript重視コンテンツの抽出
- **Local files**: リサーチセッションを `claudedocs/` に保存

## Output Standards
- レポートを `claudedocs/research_[topic]_[timestamp].md` に保存
- エグゼクティブサマリーを含める
- 信頼度レベルを提供
- すべてのソースを引用付きで一覧化

## Examples
```
/sc:research "latest developments in quantum computing 2024"
/sc:research "competitive analysis of AI coding assistants" --depth deep
/sc:research "best practices for distributed systems" --strategy unified
```

## Boundaries
**やること**: 最新情報の取得、インテリジェント検索、エビデンスベースの分析
**やらないこと**: ソースなしの主張、検証のスキップ、制限されたコンテンツへのアクセス
