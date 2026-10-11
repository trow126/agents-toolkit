# break-consensus の設計根拠（実証研究・先行事例）

2026-07-23 調査。各 Stage の設計判断を支える一次情報と、設計上の限界の明示。

## なぜ「合意領域の可視化と封鎖」か（Stage 2）

- LLM 支援の発想はユーザー間で有意に均質化する: Anderson et al., C&C 2024. https://arxiv.org/abs/2402.01536
- 生成 AI は個人の novelty を上げるが集合的多様性を下げる: Doshi & Hauser, Science Advances 2024. https://www.science.org/doi/10.1126/sciadv.adn5290
- LLM 研究アイデア生成で 4000 の seed idea 中、非重複はわずか約 200（~5%）: Si, Yang & Hashimoto, ICLR 2025. https://arxiv.org/abs/2409.04109
- フィードバックで調整したモデルと書くと、書かれた内容の多様性が下がる: Padmakumar & He, ICLR 2024. https://arxiv.org/abs/2309.05196
- 例示への曝露が発想を例示へ引き寄せる（design fixation）: Jansson & Smith 1991（古典）。「よくある解を列挙してから離れる」の実証的背骨
- 分布として k 案 + 確率を出させ、裾から取ると創作タスクで多様性が 1.6-2.1 倍（Verbalized Sampling、abstract）。同論文は mode collapse の原因を選好データの typicality bias に求める: https://arxiv.org/abs/2510.01171 — 「mode を可視化してから外す」という本 skill の Stage 2 に最も近い公開手法
- 注意: 「共通解を列挙して明示的に禁止する」手続きそのものの直接検証研究は見つかっていない（2026-07 時点）。本 skill の独自部分であり、効果は Stage 7 の実験で確認する

## なぜ「前提破壊」か（Stage 3)

- 直接の統制実験は薄い。最も近い実証は McCaffrey の Generic Parts Technique（Psychological Science 2012、機能固着の除去で洞察問題の解決率 +67%）
- （履歴）旧版の操作メニュー（削除/反転/ゼロ/100倍ほか）は SCAMPER・ラテラルシンキング系の伝統操作を厳格化したもの。現行の手順2はメニューを持たず、assumption inversion を3つの生成機構の1つとして使う

## なぜ「構造的対応が実在する異分野移植」か（Stage 4）

- 遠い分野・低頻度の例示ほど novel な設計を生む: Chan, Fu, Schunn et al., JMD 2011. https://asmedigitalcollection.asme.org/mechanicaldesign/article-abstract/133/8/081004/478279/
- ただし「遠すぎる類推」は逆効果（sweet spot が存在）: Fu et al. 2013 — 表面的比喩でなく構造対応（対応関係 5 項目）を採用条件にする理由
- 実務の設計チームは近い類推で前進する（in-vivo）: Chan & Schunn, Cognitive Science 2015. https://onlinelibrary.wiley.com/doi/full/10.1111/cogs.12127
- BioTRIZ（Vincent et al. 2006）: 生物系の解は情報・構造で解く傾向 — エネルギー投入型の定石から離れる移植元として有効

## なぜ「生成原理の強制多様化」か（Stage 5）

- frontier LLM は人間より distinct な答えが少ない（NoveltyBench）: https://arxiv.org/abs/2504.05228
- 単に「もっと出せ」は同一原理の言い換えを量産する。CoT 型の多様化プロンプトで人間集団に近づくがまだ届かない: Meincke, Mollick, Terwiesch 2024. https://arxiv.org/abs/2402.01727
- persona を付けると語彙の多様性は上がるが、persona の詳細を足しても上積みは小さい（合成データの語彙多様性で測定）: https://arxiv.org/html/2505.17390 。日常的な persona は多様なサンプリングの手がかりとして働き、CoT と組み合わせると人間より多様なアイデアが出るという報告もある: https://arxiv.org/abs/2602.20408 （どちらも旧版の原理タグ quota の根拠ではなくなった。現行手順に quota はない）

## なぜ「検索に基づく独立 novelty 監査」か（Stage 6）

- 検索に基づかない LLM の novelty 自己判定は信頼できない: AI Scientist の novelty check の浅さの独立評価 https://arxiv.org/html/2502.14297v3 、LLM-as-judge の限界 https://arxiv.org/pdf/2606.12071
- retrieval-grounded な比較（広く検索 → 絞る → facet 比較）の上積みは小さい（最大で約16点）。安価な prompt だけの judge が Idea Novelty Checker（SDP 2025, https://arxiv.org/abs/2506.22026）を約30分の1のコストで上回り、judge は手がかりに敏感（Sternlicht et al., arXiv 2610.02022）。監査の価値は判定の精度ではなく、人が確かめられる URL を集めることにある
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

- 「合意列挙 → 封鎖」は直接の実証が薄い手続き。falsifiable: `--solo` / `--cross` の実行で、probe の baseline を封鎖した run と封鎖しない run を比べ、候補の非重複率と stress test の生存率を見れば検証できる
- cross-provider（既定の `--cross`）は多様性を保証しない。異なるモデルの出力同士も収束する（Artificial Hivemind, NeurIPS 2025 D&B, https://arxiv.org/abs/2510.22954）。両 worker の一致は正しさや非合意の証拠ではない
- novelty 監査は検索範囲に依存する。「新規らしい」は「調査範囲で未発見」以上を意味しない

## 2026-10 更新: baseline probe と blind prior-art audit（手順1と4）

### 根拠

- Opus 5.5 は方向づけがないと少数の既定に落ち、「ありがちを避けて」という一般的な指示は既定を別の既定に入れ替えるだけで、避けたいものを具体的に並べたリストが効く。初回の出力を見てリストを伸ばす（Anthropic, Prompting Claude Opus 5.5「Frontend design defaults」）。https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5
- 単純な prompt で独創性が上がるが、モデル間の均質化は残る（IDEAFix, arXiv 2606.00875）。「出した案をカテゴリ分けしてその外で出させる」という手法の帰属は abstract では確認できない [unverified: abstract only]。https://arxiv.org/abs/2606.00875
- LLM judge の novelty 判定は不安定で、「査読者が片方を新規と判断した」と伝えるだけで同じペアの半数以上で判定が反転し、精度が50点以上動く。検索の上積みは小さい（Sternlicht et al., arXiv 2610.02022）。https://arxiv.org/abs/2610.02022

### 実測（2026-10-11、前回の --cross run の brief 1本、Claude 側のみ）

- baseline probe: 手順なしの fresh context 5体の回答は15の塊になった。前回の自己列挙の baseline（19項目）が覆ったのは3塊（20%）。前回の「非合意」候補16件のうち13件が probe の塊に入っていた。自己列挙では本当の mode を取りこぼす
- blind audit: 中立化した11候補に対し、fresh context の監査役が前回の記憶ベースの確認に無い先行事例を7件で URL 付きで見つけた（KNOWN 7、PARTIAL 4、NOT_FOUND 0）。「新規な案」と伝えた監査役とは3件で判定が変わった（反復なしなので、手がかりの効果とばらつきは区別できない）
- 不採用: 生成ストリームごとの外部乱数シード（persona と clipping の要約）は、塊の数が 13 対 14 で事前登録の基準（20%増）を満たさなかった
- 限界: brief は1本で、probe は Opus 5.5、前回の worker は Fable と Astra。brief の「What counts as useful」が回答を誘導していた
