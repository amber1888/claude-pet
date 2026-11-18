#!/bin/bash
# 拉取角色素材（CC BY-NC-SA 4.0），放到 characters/ 和 assets/。这些素材不进本仓库，都固定在 upstream/ 里记录的提交，保证每次拉到的一样：
#   claudia-pet（kirito1207）@ upstream/claudia-pet-COMMIT：默认形象 characters/claude（立绘 + 动画精灵图）、图标
#   CrossPet（lokicorvus）    @ upstream/crosspet-COMMIT   ：其他形象，只取 claudia 的衣服（见下面 SKINS）
# 用法：./scripts/fetch-assets.sh [--force]   （--force 全部重新拉）
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
FORCE="${1:-}"
SKINS="claude-saint"   # CrossPet 里 skinOf 是 claude 的完整形象（egg-* 是和别的角色串门的彩蛋，不要）

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 只取仓库里的几个路径：浅克隆 + 稀疏检出，不下载别的角色的图
fetch() {   # fetch <仓库> <提交> <目录> <路径…>
  local repo="$1" commit="$2" dir="$3"; shift 3
  echo "拉取 ${repo} @ ${commit}（$*）…"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$repo"
  git -C "$dir" sparse-checkout set --no-cone "$@"
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$commit"
  git -C "$dir" checkout -q FETCH_HEAD
}

# ---- 默认形象和图标 ----
if [ -f characters/claude/character.json ] && [ -f assets/AppIcon.png ] && [ "$FORCE" != "--force" ]; then
  echo "默认形象已存在"
else
  COMMIT="$(tr -d '[:space:]' < upstream/claudia-pet-COMMIT)"
  mkdir "$TMP/claudia"
  fetch https://github.com/kirito1207/claudia-pet.git "$COMMIT" "$TMP/claudia" /characters/ /icon/AppIcon.png
  rm -rf "$ROOT/characters" "$ROOT/assets"
  mkdir -p "$ROOT/assets"
  cp -R "$TMP/claudia/characters" "$ROOT/characters"
  cp "$TMP/claudia/icon/AppIcon.png" "$ROOT/assets/AppIcon.png"
fi

# ---- 其他形象（CrossPet） ----
need=""
for s in $SKINS; do
  if [ ! -f "characters/$s/character.json" ] || [ "$FORCE" = "--force" ]; then need="$need $s"; fi
done
if [ -z "$need" ]; then
  echo "其他形象已存在：$SKINS"
else
  COMMIT="$(tr -d '[:space:]' < upstream/crosspet-COMMIT)"
  mkdir "$TMP/crosspet"
  paths=""
  for s in $need; do paths="$paths /characters/$s/"; done
  # shellcheck disable=SC2086
  fetch https://github.com/lokicorvus/crosspet.git "$COMMIT" "$TMP/crosspet" $paths
  for s in $need; do
    rm -rf "$ROOT/characters/$s"
    cp -R "$TMP/crosspet/characters/$s" "$ROOT/characters/$s"
    cat > "$ROOT/characters/$s/SOURCE.md" <<EOF
# $s

来自 [CrossPet](https://github.com/lokicorvus/crosspet)（lokicorvus）的 \`characters/$s\`，提交 \`$COMMIT\`，原样复制没有改动。
按 CC BY-NC-SA 4.0 授权：须署名、不得商用、相同方式共享。来源和原作者见 ../LICENSE.md 与项目 NOTICE.md。
EOF
  done
fi

echo "完成：characters/（$(du -sh "$ROOT/characters" | cut -f1)）：$(ls -d "$ROOT"/characters/*/ | xargs -n1 basename | tr '\n' ' ')"
