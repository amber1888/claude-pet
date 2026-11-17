#!/bin/bash
# 从 claudia-pet 上游拉取角色立绘、动画精灵图和图标（CC BY-NC-SA 4.0），放到 characters/ 和 assets/。
# 这些素材不进本仓库；固定在 upstream/claudia-pet-COMMIT 记录的提交，保证每次拉到的一样。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO="https://github.com/kirito1207/claudia-pet.git"
COMMIT="$(tr -d '[:space:]' < upstream/claudia-pet-COMMIT)"

if [ -f characters/claude/character.json ] && [ -f assets/AppIcon.png ] && [ "${1:-}" != "--force" ]; then
  echo "素材已存在（重新拉取用 --force）"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "拉取 $REPO @ $COMMIT …"
git -C "$TMP" init -q
git -C "$TMP" remote add origin "$REPO"
git -C "$TMP" fetch -q --depth 1 origin "$COMMIT"
git -C "$TMP" checkout -q FETCH_HEAD

rm -rf "$ROOT/characters" "$ROOT/assets"
mkdir -p "$ROOT/assets"
cp -R "$TMP/characters" "$ROOT/characters"
cp "$TMP/icon/AppIcon.png" "$ROOT/assets/AppIcon.png"
echo "完成：characters/（$(du -sh "$ROOT/characters" | cut -f1)），assets/AppIcon.png"
