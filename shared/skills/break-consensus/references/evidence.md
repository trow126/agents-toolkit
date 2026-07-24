# break-consensus の設計根拠（実証研究・先行事例）

2026-07-23 調査。各 Stage の設計判断を支える一次情報と、設計上の限界の明示。

## なぜ「合意領域の可視化と封鎖」か（Stage 2）

- LLM 支援の発想はユーザー間で有意に均質化する: Anderson et al., C&C 2024. https://arxiv.org/abs/2402.01536
- 生成 AI は個人の novelty を上げるが集合的多様性を下げる: Doshi & Hauser, Science Advances 2024. https://www.science.org/doi/10.1126/sciadv.adn5290
- LLM 研究アイデア生成で 4000 の seed idea 中、非重複はわずか約 200（~5%）: Si, Yang & Hashimoto, ICLR 2025. https://arxiv.org/abs/2409.04109
- RLHF/alignment が出力多様性を下げる（mode collapse は typicality bias に由来）: Padmakumar & He, ICLR 2024. https://arxiv.org/abs/2309.05196
- 例示への曝露が発想を例示へ引き寄せる（design fixation）: Jansson & Smith 1991（古典）。「よくある解を列挙してから離れる」の実証的背骨
- 分布として k 案 + 確率を出させ、裾から取ると多様性が 2-3 倍（Verbalized Sampling）: https://arxiv.org/abs/2510.01171 — 「mode を可視化してから外す」という本 skill の Stage 2 に最も近い公開手法
- 注意: 「共通解を列挙して明示的に禁止する」手続きそのものの直接検証研究は見つかっていない（2026-07 時点）。本 skill の独自部分であり、効果は Stage 7 の実験で確認する

## なぜ「前提破壊」か（Stage 3)

- 直接の統制実験は薄い。最も近い実証は McCaffrey の Generic Parts Technique（Psychological Science 2012、機能固着の除去で洞察問題の解決率 +67%）
- 操作メニュー（削除/反転/ゼロ/100倍/主体変更/時間逆転/成功失敗入替/解かない/副作用主目的化)は SCAMPER・ラテラルシンキング系の伝統操作を「探索空間の変化を説明できた操作だけ残す」形で厳格化したもの

## なぜ「構造的対応が実在する異分野移植」か（Stage 4）

- 遠い分野・低頻度の例示ほど novel な設計を生む: Chan, Fu, Schunn et al., JMD 2011. https://asmedigitalcollection.asme.org/mechanicaldesign/article-abstract/133/8/081004/478279/
- ただし「遠すぎる類推」は逆効果（sweet spot が存在）: Fu et al. 2013 — 表面的比喩でなく構造対応（対応関係 5 項目）を採用条件にする理由
- 実務の設計チームは近い類推で前進する（in-vivo）: Chan & Schunn, Cognitive Science 2015. https://onlinelibrary.wiley.com/doi/full/10.1111/cogs.12127
- BioTRIZ（Vincent et al. 2006）: 生物系の解は情報・構造で解く傾向 — エネルギー投入型の定石から離れる移植元として有効

## なぜ「生成原理の強制多様化」か（Stage 5）

- frontier LLM は人間より distinct な答えが少ない（NoveltyBench）: https://arxiv.org/abs/2504.05228
- 単に「もっと出せ」は同一原理の言い換えを量産する。CoT 型の多様化プロンプトで人間集団に近づくがまだ届かない: Meincke, Mollick, Terwiesch 2024. https://arxiv.org/abs/2402.01727
- persona の付け替えだけでは多様性がほぼ増えない: https://arxiv.org/html/2505.17390 — 原理タグの重複禁止という構造的制約を使う理由
- 原理タグ quota の直接検証研究はない（本 skill の独自部分）

## なぜ「検索に基づく独立 novelty 監査」か（Stage 6）

- 検索に基づかない LLM の novelty 自己判定は信頼できない: AI Scientist の novelty check の浅さの独立評価 https://arxiv.org/html/2502.14297v3 、LLM-as-judge の限界 https://arxiv.org/pdf/2606.12071
- retrieval-grounded な比較（広く検索 → 絞る → facet 比較）が現状最良: Idea Novelty Checker, SDP 2025. https://arxiv.org/abs/2506.22026
- 特許実務の prior-art search の移植: 語ではなく機能・機構で検索し、分類・引用連鎖で recall を上げ、カバレッジを文書化してから止める（WIPO/USPTO の審査実務）

## なぜ「反証可能な最小実験」か（Stage 7）

- 紙上で novel と評価されたアイデアは、実行後に評価が急落する（ideation–execution gap）: https://arxiv.org/abs/2506.20803
- 機械による本物の novelty の存在証明は「生成 + 自動評価器 + 多様性維持」の反復（FunSearch, Nature 2023）: https://www.nature.com/articles/s41586-023-06924-6 — 評価器 = 本 skill では反証条件付き最小実験

## 既存 skill との差分（本 skill 自身の novelty 監査、2026-07-23 実施）

- obra/superpowers `brainstorming`: 要件明確化ゲート（Socratic 質問 → 設計文書）。novelty・反収束機構なし
- UditAkhourii/adhd: 並列 diverge + critic 収束。最も近いが、合意封鎖・前提破壊・外部 novelty 検索・実験変換なし
- 技法メニュー型（SCAMPER/Six Hats/TRIZ 列挙系）: 操作の列挙のみで、baseline 封鎖・原理重複禁止・監査の強制がない
- 名称 "break-consensus" の既存衝突: 完全一致なし（blockchain の "consensus-breaking change"、ACL 2026 CoVerRL "Breaking the Consensus Trap" は別領域）

## 設計上の限界（明示）

- 「合意列挙 → 封鎖」「原理タグ quota」は直接の実証がない独自手続き。falsifiable: 本 skill の light/standard 実行で、封鎖なし brainstorming と候補の非重複率・採用後の生存率を比較すれば検証できる
- novelty 監査は検索範囲に依存する。「新規らしい」は「調査範囲で未発見」以上を意味しない
