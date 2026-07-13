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
# -e: worktree 等で .git がファイルの場合も対応
if [[ -e "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" config core.hooksPath claude/githooks
  echo "hooksPath: claude/githooks"
fi
