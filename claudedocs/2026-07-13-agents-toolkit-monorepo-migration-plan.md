# agents-toolkit モノレポ統合 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ~/.claude(claude-toolkit)・~/.agents・~/.codex を単一 public リポジトリ agents-toolkit に統合し、symlink 3本で現行運用を無変更のまま継続させる。

**Architecture:** claude-toolkit を GitHub 上で rename し、worktree を ~/agents-toolkit へ移設。追跡ファイルを git mv で claude/ へ純 rename 移動し、shared/(旧 ~/.agents)と codex/(旧 ~/.codex、default-deny の whitelist .gitignore)を追加。旧パスは丸ごと symlink で維持。

**Tech Stack:** bash / git / gh CLI。設計: `claudedocs/brainstorm/2026-07-13-agents-toolkit-monorepo-design.md`

## Global Constraints

- リポジトリは **public**。私的プロジェクト名・トークン・機微情報を追跡対象に含めない(codex/config.toml は絶対に追跡しない)
- Task 5(切替)は **Claude Code・Codex・cron/hooks を全停止した素のシェル**からユーザーが実行する。Claude セッション内で実行してはならない
- git mv は **content 変更なしの純 rename 単独コミット**(`git log --follow` 追従性の確保)
- main/master への force-push 禁止。~/.claude/settings.json はセッション内で編集しない
- バックアップ(tar と旧構成への復元手順)が確認できるまで元データを削除しない

---

### Task 1: sync-shared-rules.sh の mv→cp 修正

**Files:**
- Modify: `~/.agents/bin/sync-shared-rules.sh:35`

**Interfaces:**
- Produces: symlink を破壊しない sync スクリプト(Task 5 で shared/bin/ へそのまま移設される)

- [ ] **Step 1: 修正前の ~/.codex/AGENTS.md をバックアップ**

```bash
cp ~/.codex/AGENTS.md /tmp/claude-1000/-home-trow126/fb734d68-a0c7-4d80-a287-c5c25e27e001/scratchpad/AGENTS.md.before
```

- [ ] **Step 2: mv を cp + rm に変更**

`~/.agents/bin/sync-shared-rules.sh` の

```bash
  mv "$tmp" "$target"
```

を以下に置換(cp は dest が symlink でも実体に追従書き込みするため symlink を温存する):

```bash
  cp "$tmp" "$target"
  rm -f "$tmp"
```

- [ ] **Step 3: sync を実行して冪等性を検証**

```bash
bash ~/.agents/bin/sync-shared-rules.sh
diff /tmp/claude-1000/-home-trow126/fb734d68-a0c7-4d80-a287-c5c25e27e001/scratchpad/AGENTS.md.before ~/.codex/AGENTS.md
```

Expected: sync が `synced shared:... -> ...` を4行出力し、diff は差分なし(終了コード0)。差分が出た場合は正本とマーカー区間の乖離なので、内容を確認してから進む。

- [ ] **Step 4: バックアップを削除**

```bash
rm /tmp/claude-1000/-home-trow126/fb734d68-a0c7-4d80-a287-c5c25e27e001/scratchpad/AGENTS.md.before
```

(コミットは不可 — ~/.agents はまだ git 管理外。Task 5 の統合コミットに含まれる)

---

### Task 2: 公開前機微情報監査

**Files:**
- 読み取りのみ: `~/.agents/` 全体、`~/.codex/AGENTS.md`、`~/.codex/hooks.json`、`~/.codex/rules/`、`~/.codex/skills/`、`~/.codex/herdr-agent-state.sh`

**Interfaces:**
- Produces: 追跡可否の判定結果。**私的情報が見つかったファイルは Task 3 の gitignore.root の allowlist から外す**か、ユーザーに報告して判断を仰ぐ

- [ ] **Step 1: トークン・シークレットのスキャン**

```bash
grep -rniE 'ghp_[A-Za-z0-9]|github_pat_|sk-[A-Za-z0-9]{20}|xox[bpo]-|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY' \
  ~/.agents/ ~/.codex/AGENTS.md ~/.codex/hooks.json ~/.codex/rules/ ~/.codex/skills/ ~/.codex/herdr-agent-state.sh
```

Expected: ヒット0件(終了コード1)。ヒットした場合は該当ファイルを追跡対象から除外し、ユーザーに報告する。

- [ ] **Step 2: 私的プロジェクト名のスキャン**

```bash
grep -rniE 'keiba|ChaoScale|flashloan|PTCGZero|us-stock|sector_leadlag' \
  ~/.agents/ ~/.codex/AGENTS.md ~/.codex/hooks.json ~/.codex/rules/ ~/.codex/skills/ ~/.codex/herdr-agent-state.sh
```

Expected: ヒット0件。ヒットした場合、CLAUDE.md の「公開リポジトリに固有名を書かない」ルールに基づき、該当ファイルを allowlist から外すか記述を汎用化する(ユーザーに報告して判断)。

- [ ] **Step 3: 絶対パスの確認(情報提供のみ)**

```bash
grep -rln '/home/trow126' ~/.codex/AGENTS.md ~/.codex/hooks.json ~/.codex/rules/ ~/.codex/skills/ ~/.codex/herdr-agent-state.sh ~/.agents/
```

Expected: hooks.json 等がヒットしてよい。ユーザー名 trow126 は既に public(claude-toolkit の settings.json で公開済み)のためブロッカーではない。件数を記録するのみ。

- [ ] **Step 4: 監査結果をユーザーに報告**

ヒット一覧と追跡可否の判定を提示。Step 1-2 でヒットがあった場合はここで停止し、ユーザーの判断を待つ。

---

### Task 3: 移行キットの作成(~/agents-toolkit-kit/)

**Files:**
- Create: `~/agents-toolkit-kit/bootstrap.sh`
- Create: `~/agents-toolkit-kit/gitignore.root`
- Create: `~/agents-toolkit-kit/README.root.md`
- Create: `~/agents-toolkit-kit/migrate.sh`

**Interfaces:**
- Consumes: Task 2 の監査結果(allowlist の増減)
- Produces: Task 5 でユーザーが実行する自己完結スクリプト一式。migrate.sh は同ディレクトリの他3ファイルを参照する

- [ ] **Step 1: bootstrap.sh を作成**

```bash
#!/usr/bin/env bash
# bootstrap.sh — agents-toolkit の設定ディレクトリ symlink を作成する(冪等)
# 新マシンセットアップ: git clone <repo> ~/agents-toolkit && bash ~/agents-toolkit/bootstrap.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      echo "ok: $dest -> $src"
      return
    fi
    echo "ERROR: $dest は別の場所 ($current) を指す symlink です" >&2
    exit 1
  fi
  if [[ -e "$dest" ]]; then
    echo "ERROR: $dest に実体が存在します。手動で退避してから再実行してください" >&2
    exit 1
  fi
  ln -s "$src" "$dest"
  echo "linked: $dest -> $src"
}

link "$REPO_DIR/claude" "$HOME/.claude"
link "$REPO_DIR/shared" "$HOME/.agents"
link "$REPO_DIR/codex" "$HOME/.codex"

# gitleaks pre-commit hook の有効化(core.hooksPath は .git/config 保存のためマシンごとに必要)
if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" config core.hooksPath claude/githooks
  echo "hooksPath: claude/githooks"
fi
```

- [ ] **Step 2: gitignore.root を作成(codex は default-deny の whitelist 方式)**

Task 2 で除外が増えた場合は allowlist(`!codex/...` 行)から該当行を削る。

```gitignore
# ============================================================
# agents-toolkit ルート .gitignore
# 方針: 各エージェントの runtime データは default-deny。
#       codex/ は whitelist 方式 — 追跡したい設定ファイルだけ ! で許可する。
#       claude/ の runtime 除外は claude/.gitignore が担当(従来運用のまま)。
# エージェント追加時: <agent>/* を deny し、設定ファイルだけ allowlist する。
# ============================================================

# --- codex: default-deny + allowlist ---
codex/*
!codex/AGENTS.md
!codex/hooks.json
!codex/herdr-agent-state.sh
!codex/rules/
!codex/skills/

# 二重防御(allowlist ミス時の保険)
codex/auth.json
codex/config.toml
codex/gh.config.toml
codex/*.sqlite
codex/*.sqlite-*
codex/history.jsonl
codex/session_index.jsonl
codex/installation_id

# --- 一時ファイル全般 ---
*.bak
*.tmp
```

- [ ] **Step 3: README.root.md を作成**

```markdown
# agents-toolkit

AI エージェント設定の一元管理モノレポ(旧 claude-toolkit)。

## レイアウト

| ディレクトリ | 実体の利用パス | 内容 |
|---|---|---|
| `claude/` | `~/.claude` (symlink) | Claude Code 設定。runtime 除外は `claude/.gitignore` |
| `codex/` | `~/.codex` (symlink) | Codex CLI 設定。ルート `.gitignore` の whitelist 方式で default-deny |
| `shared/` | `~/.agents` (symlink) | エージェント横断の共有ルール正本 + sync スクリプト |

## セットアップ(新マシン)

```bash
git clone https://github.com/trow126/agents-toolkit.git ~/agents-toolkit
bash ~/agents-toolkit/bootstrap.sh
```

## 共有ルールの更新

正本 `shared/rules/*.md` を編集後、`shared/bin/sync-shared-rules.sh` を実行して
`codex/AGENTS.md` のマーカー区間へ同期する(Claude 側は `@~/.agents/rules/*.md` を実行時 import)。

## エージェント追加ルール

1. `<agent>/` ディレクトリを作成し、config ディレクトリを**丸ごと** symlink する(per-file symlink は設定ファイル追加に追随できないため禁止)
2. ルート `.gitignore` に `<agent>/*` の default-deny + 設定ファイルの allowlist を追加
3. `bootstrap.sh` に `link` を1行追加

## 注意

- このリポジトリは **public**。私的プロジェクト名・トークン・trust 設定(`codex/config.toml`)を追跡しない
- 新しい設定ファイルを追跡したい場合はルート `.gitignore` の allowlist に明示追加する(default-deny のため自動では追跡されない)
```

- [ ] **Step 4: migrate.sh を作成**

```bash
#!/usr/bin/env bash
# migrate.sh — claude-toolkit を agents-toolkit モノレポへ移行する(一度きり)
# 実行条件: Claude Code / Codex を全停止した素のシェルから bash ~/agents-toolkit-kit/migrate.sh
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HOME/agents-toolkit"
BRANCH="feat/monorepo-restructure"

# ---------- 前提チェック ----------
for p in claude codex; do
  if pgrep -x "$p" >/dev/null 2>&1; then
    echo "ERROR: $p プロセスが稼働中です。終了してから再実行してください" >&2
    exit 1
  fi
done
for d in "$HOME/.claude" "$HOME/.agents" "$HOME/.codex"; do
  if [[ -L "$d" ]]; then
    echo "ERROR: $d は既に symlink です(移行済み?)" >&2
    exit 1
  fi
done
if [[ -e "$REPO" ]]; then
  echo "ERROR: $REPO が既に存在します" >&2
  exit 1
fi
for f in "$KIT/bootstrap.sh" "$KIT/gitignore.root" "$KIT/README.root.md"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: 移行キットが不完全です: $f がありません" >&2
    exit 1
  fi
done
if ! git -C "$HOME/.claude" diff --quiet || ! git -C "$HOME/.claude" diff --cached --quiet; then
  echo "ERROR: ~/.claude に未コミットの変更があります" >&2
  exit 1
fi

# ---------- バックアップ(.agents と .codex の設定部分) ----------
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/agents-migration-backup-$STAMP.tar.gz"
tar --exclude='.codex/cache' --exclude='.codex/tmp' --exclude='.codex/log' \
    --exclude='.codex/sessions' --exclude='.codex/shell_snapshots' \
    --exclude='.codex/backups' --exclude='.codex/plugins' \
    -czf "$BACKUP" -C "$HOME" .agents .codex
echo "backup: $BACKUP"

# ---------- 1. リポジトリ移設 ----------
mv "$HOME/.claude" "$REPO"
cd "$REPO"
git checkout master
git checkout -b "$BRANCH"

# ---------- 2. 純 rename コミット: 追跡ファイルを claude/ へ ----------
mkdir claude
git ls-files | cut -d/ -f1 | sort -u | while IFS= read -r top; do
  git mv "$top" claude/
done
# githooks/ が claude/ 配下へ移動したため hooksPath を追従(gitleaks の黙殺防止)
git config core.hooksPath claude/githooks
git commit -m "refactor: claude-toolkit の全追跡ファイルを claude/ へ移動(純 rename)

Co-Authored-By: Claude <noreply@anthropic.com>"

# 未追跡の runtime データも claude/ へ物理移動
shopt -s dotglob
for item in *; do
  case "$item" in .git|claude) continue ;; esac
  mv "$item" claude/
done
shopt -u dotglob

# ---------- 3. shared/ と codex/ の取り込み ----------
mv "$HOME/.agents" "$REPO/shared"
mv "$HOME/.codex" "$REPO/codex"

# ---------- 4. ルートファイル配置とコミット ----------
cp "$KIT/gitignore.root" "$REPO/.gitignore"
cp "$KIT/bootstrap.sh" "$REPO/bootstrap.sh"
cp "$KIT/README.root.md" "$REPO/README.md"
chmod +x "$REPO/bootstrap.sh"

git add .gitignore bootstrap.sh README.md shared codex

# 機微ファイル混入の最終ゲート(No Fallback: 黙って進まない)
if git diff --cached --name-only | grep -qE 'auth\.json|config\.toml|gh\.config|\.sqlite|history\.jsonl|installation_id'; then
  echo "ERROR: 機微ファイルがステージされています。中断します" >&2
  git diff --cached --name-only >&2
  exit 1
fi
echo "--- ステージ内容(codex/ と shared/) ---"
git diff --cached --stat

git commit -m "feat: shared/(旧 ~/.agents)と codex/(旧 ~/.codex)を統合し monorepo 化

Co-Authored-By: Claude <noreply@anthropic.com>"

# ---------- 5. symlink 作成 ----------
bash "$REPO/bootstrap.sh"

echo ""
echo "==== 移行完了 ===="
echo "次: 新しいシェルで claude / codex を起動してスモークテスト(計画 Task 6)。"
echo "    push はスモークテスト合格後。ロールバックは:"
echo "    rm ~/.claude ~/.agents ~/.codex(symlink 削除)"
echo "    mv $REPO ~/.claude && cd ~/.claude && git checkout master"
echo "    mv ~/.claude/shared ~/.agents && mv ~/.claude/codex ~/.codex"
echo "    バックアップ: $BACKUP"
```

- [ ] **Step 5: 静的検証**

```bash
bash -n ~/agents-toolkit-kit/bootstrap.sh
bash -n ~/agents-toolkit-kit/migrate.sh
```

Expected: 両方とも出力なし(構文エラーなし)。shellcheck が利用可能なら `shellcheck ~/agents-toolkit-kit/*.sh` も実行し、error レベルの指摘0件を確認。

- [ ] **Step 6: bootstrap.sh のガード動作をテスト**

偽の HOME を使い、実環境に触れずに冪等性と衝突検出を確認する(bootstrap.sh は REPO_DIR = スクリプト設置ディレクトリ基準で symlink を張るため、キットのまま実行してよい。リンク先の実在は ln -s に不要):

```bash
FAKE=/tmp/claude-1000/-home-trow126/fb734d68-a0c7-4d80-a287-c5c25e27e001/scratchpad/bs-test
mkdir -p "$FAKE"
HOME="$FAKE" bash ~/agents-toolkit-kit/bootstrap.sh   # 1回目
HOME="$FAKE" bash ~/agents-toolkit-kit/bootstrap.sh   # 2回目(冪等)
mkdir "$FAKE/real-dir"; mv "$FAKE/.claude" "$FAKE/.claude.bak"; mkdir "$FAKE/.claude"
HOME="$FAKE" bash ~/agents-toolkit-kit/bootstrap.sh; echo "exit=$?"   # 3回目(衝突)
rm -rf "$FAKE"
```

Expected: 1回目は `linked:` 3行(+ hooksPath 行は .git がないため出ない)、2回目は `ok:` 3行、3回目は「実体が存在します」の ERROR で exit=1。確認後に掃除。

---

### Task 4: リポジトリ準備(merge・push・GitHub rename)

**Files:**
- Modify: git 状態のみ(~/.claude リポジトリ、GitHub リモート)

**Interfaces:**
- Consumes: Task 2 の監査合格
- Produces: rename 済みリモート(trow126/agents-toolkit)と push 済み master。Task 5 の migrate.sh はこの状態を前提とする

- [ ] **Step 1: design branch を master へマージ**

```bash
git -C ~/.claude checkout master
git -C ~/.claude merge docs/agents-toolkit-monorepo-design
git -C ~/.claude branch -d docs/agents-toolkit-monorepo-design
```

Expected: fast-forward またはマージコミット成功。

- [ ] **Step 2: master を push(未 push commit 含む)**

```bash
git -C ~/.claude push origin master
```

Expected: 成功。rejected の場合は `git pull --rebase` してから再 push(force-push 禁止)。

- [ ] **Step 3: GitHub リポジトリを rename**

```bash
gh repo rename agents-toolkit -R trow126/claude-toolkit --yes
```

Expected: `renamed repository trow126/agents-toolkit` 相当の成功出力。旧 URL は GitHub が自動リダイレクト。

- [ ] **Step 4: ローカル remote URL を更新して検証**

```bash
git -C ~/.claude remote set-url origin https://github.com/trow126/agents-toolkit.git
git -C ~/.claude remote -v
git -C ~/.claude fetch origin
```

Expected: remote -v が agents-toolkit.git を示し、fetch が成功する。

---

### Task 5: 切替実行【ユーザー手動・セッション外】

**Files:**
- 実行: `~/agents-toolkit-kit/migrate.sh`

**Interfaces:**
- Consumes: Task 3 のキット、Task 4 の push/rename 済み状態
- Produces: ~/agents-toolkit(feat/monorepo-restructure ブランチ、コミット2つ)+ symlink 3本

- [ ] **Step 1: ユーザーへの実行依頼**

Claude セッション終了後、素のシェルから以下を実行してもらう:

```bash
# 1. 稼働確認(何も表示されないこと)
pgrep -ax claude; pgrep -ax codex

# 2. 移行実行
bash ~/agents-toolkit-kit/migrate.sh
```

Expected: `backup: ...` → git mv のコミット2つ → `--- ステージ内容 ---` に codex/AGENTS.md, codex/hooks.json, codex/rules/*, codex/skills/*, shared/* のみ → `linked:` 3行 → `==== 移行完了 ====`。
ERROR で停止した場合はメッセージに従い解消してから再実行(スクリプトは途中状態を作る前に前提チェックで止まる設計)。

---

### Task 6: スモークテストと確定【新セッション】

**Files:**
- 検証のみ。合格後に push とクリーンアップ

**Interfaces:**
- Consumes: Task 5 完了状態

- [ ] **Step 1: symlink と git 状態の確認**

```bash
ls -l ~/.claude ~/.agents ~/.codex
git -C ~/agents-toolkit status --porcelain
```

Expected: 3つとも `-> /home/trow126/agents-toolkit/...` の symlink。status は空(runtime データが untracked として現れない = .gitignore が機能)。

- [ ] **Step 2: Claude Code のスモークテスト**

プロジェクトディレクトリから claude を起動($HOME 直下起動は禁止ルールあり):

```bash
cd ~/agents-toolkit && claude -p "CLAUDE.md に import されている no-fallback ポリシーの1行目をそのまま引用して"
```

Expected: 「サイレントなエラー握りつぶし禁止…」の引用が返る(@~/.agents/rules import が symlink 経由で解決)。SessionStart hook のエラーが出ないこと。

- [ ] **Step 3: Codex CLI のスモークテスト**

```bash
codex --version
codex exec --skip-git-repo-check "AGENTS.md の言語ルールを一行で答えて"
```

Expected: バージョン表示、および「回答は日本語…」相当の応答(~/.codex symlink 経由で AGENTS.md・auth.json が読めている)。

- [ ] **Step 4: push と master への統合**

```bash
git -C ~/agents-toolkit push -u origin feat/monorepo-restructure
git -C ~/agents-toolkit checkout master
git -C ~/agents-toolkit merge feat/monorepo-restructure
git -C ~/agents-toolkit push origin master
git -C ~/agents-toolkit branch -d feat/monorepo-restructure
```

Expected: すべて成功。push 時に GitHub 上で内容を一目確認(codex/config.toml が存在しないこと)。

- [ ] **Step 5: 履歴追従の確認**

```bash
git -C ~/agents-toolkit log --follow --oneline claude/CLAUDE.md | tail -3
```

Expected: rename 前(claude-toolkit 時代)のコミットが表示される。

- [ ] **Step 6: クリーンアップ**

```bash
rm -rf ~/agents-toolkit-kit
rm ~/agents-migration-backup-*.tar.gz
```

Expected: Step 1-5 がすべて合格していることを確認してから実行。設計ドキュメント(claudedocs/brainstorm/)は対応作業完了につき workspace ルールに従い削除してよい(履歴には残る)。

---

## ロールバック手順(Task 5-6 で問題発生時)

```bash
rm ~/.claude ~/.agents ~/.codex          # symlink 削除(実体は消えない)
mv ~/agents-toolkit/shared ~/.agents
mv ~/agents-toolkit/codex ~/.codex
mv ~/agents-toolkit ~/.claude
cd ~/.claude && git checkout master       # claude/ 配下に移った状態を戻す場合は
git reset --hard origin/master            # push 前なら reset で復元(push 後は revert)
# claude/ に物理移動した untracked runtime は mv ~/.claude/claude/* ~/.claude/ で戻す
```

GitHub rename の巻き戻しは `gh repo rename claude-toolkit -R trow126/agents-toolkit --yes`。
