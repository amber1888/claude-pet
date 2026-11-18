#!/bin/bash
# 拉取角色素材（CC BY-NC-SA 4.0），放到 characters/ 和 assets/。这些素材不进本仓库，都固定在 upstream/ 里记录的提交，保证每次拉到的一样：
#   claudia-pet（kirito1207）@ upstream/claudia-pet-COMMIT：默认形象 characters/claude（立绘 + 动画精灵图）、图标
#   CrossPet（lokicorvus）    @ upstream/crosspet-COMMIT   ：其他形象，只取 claudia 的衣服（见下面 SKINS）
#     原样用的直接复制；仓库里 looks/<形象>/ 有 poses.txt 的，按它从原图组装（图片原样，只是换个文件名当别的姿态用），
#     再放上 looks/<形象>/character.json
#   Claude-girl（wangxianda941030）@ upstream/claude-girl-COMMIT：克劳德大小姐「茶会大小姐」形象（CC BY-NC 4.0）。
#     原素材是带透明通道的 webm 动画，按 looks/claude-girl/video.txt 用 scripts/video-look.sh 转成精灵图；
#     要 ffmpeg 和 cwebp（brew install ffmpeg webp），没装就跳过这个形象，别的照常
# 用法：./scripts/fetch-assets.sh [--force]   （--force 全部重新拉）
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
FORCE="${1:-}"
# 形象 id:CrossPet 里的文件夹。egg-* 是和别的角色串门的彩蛋，只取了睡衣这套（全身站立图，能当形象用）
SKINS="claude-saint:claude-saint claude-pajamas:egg-claude-pajamas"

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
for pair in $SKINS; do
  id="${pair%%:*}"
  if [ ! -f "characters/$id/character.json" ] || [ "$FORCE" = "--force" ]; then need="$need $pair"; fi
done
if [ -z "$need" ]; then
  echo "其他形象已存在：$(for p in $SKINS; do printf '%s ' "${p%%:*}"; done)"
else
  COMMIT="$(tr -d '[:space:]' < upstream/crosspet-COMMIT)"
  mkdir "$TMP/crosspet"
  paths=""
  for pair in $need; do paths="$paths /characters/${pair#*:}/"; done
  # shellcheck disable=SC2086
  fetch https://github.com/lokicorvus/crosspet.git "$COMMIT" "$TMP/crosspet" $paths
  for pair in $need; do
    id="${pair%%:*}"; src="${pair#*:}"
    from="$TMP/crosspet/characters/$src"; to="$ROOT/characters/$id"
    rm -rf "$to"
    if [ -f "looks/$id/poses.txt" ]; then
      mkdir -p "$to"
      # poses.txt 每行：<姿态文件名> <原图文件名>（# 开头是注释）
      while read -r target source _; do
        case "$target" in ''|'#'*) continue ;; esac
        cp "$from/$source" "$to/$target"
      done < "looks/$id/poses.txt"
      cp "looks/$id/character.json" "$to/character.json"
      how="图片原样，按本项目 \`looks/$id/poses.txt\` 换了文件名当作各个姿态；\`character.json\`（设置和台词）是本项目写的"
    else
      cp -R "$from" "$to"
      how="原样复制没有改动"
    fi
    cat > "$to/SOURCE.md" <<EOF
# $id

来自 [CrossPet](https://github.com/lokicorvus/crosspet)（lokicorvus）的 \`characters/$src\`，提交 \`$COMMIT\`，${how}。
按 CC BY-NC-SA 4.0 授权：须署名、不得商用、相同方式共享。来源和原作者见 ../LICENSE.md 与项目 NOTICE.md。
EOF
  done
fi

# ---- 视频形象（片段是带透明通道的 webm，要转成精灵图）----
# 每项：形象 id|仓库|记提交号的文件|片段目录|许可文件
VIDEO_LOOKS="claude-girl|https://github.com/wangxianda941030/Claude-girl.git|upstream/claude-girl-COMMIT|clips|ASSETS_LICENSE.md"
for entry in $VIDEO_LOOKS; do
  IFS='|' read -r id repo commitfile clipdir license <<< "$entry"
  if [ -f "characters/$id/character.json" ] && [ "$FORCE" != "--force" ]; then echo "${id} 已存在"; continue; fi
  if ! command -v ffmpeg >/dev/null || ! command -v cwebp >/dev/null; then
    echo "跳过 ${id}：要 ffmpeg 和 cwebp 把它的 webm 动画转成精灵图（brew install ffmpeg webp），装好后重跑这个脚本"
    continue
  fi
  COMMIT="$(tr -d '[:space:]' < "$commitfile")"
  mkdir "$TMP/$id"
  fetch "$repo" "$COMMIT" "$TMP/$id" "/$clipdir/" "/$license"
  out="$TMP/$id-out"
  echo "转换 ${id} 的动画（要一两分钟）…"
  ./scripts/video-look.sh "$TMP/$id/$clipdir" "$out" "looks/$id/video.txt"
  # character.json：本项目写的设置台词，加上每张精灵图实际几帧（不满 120 帧的要写 to，不然会播到空白格）
  python3 -I scripts/look-frames.py "looks/$id/character.json" "$out/frames.json" "$out/character.json"
  rm "$out/frames.json"
  cp "$TMP/$id/$license" "$out/LICENSE.md"
  cat > "$out/SOURCE.md" <<EOF
# $id

动画来自 [克劳德大小姐 · Claude-girl](${repo%.git})（wangxianda941030）的 \`${clipdir}/\`，提交 \`${COMMIT}\`。
原素材是带透明通道的 WebM 动画，本项目用 \`scripts/video-look.sh\` 按 \`looks/${id}/video.txt\` 转成精灵图和静态立绘（缩放、对齐、换格式，
捧茶的几段前后接上了拿出 / 收起茶杯）；\`character.json\`（姿态对应、台词）是本项目写的，部分台词取自 Claude-girl 的 pet-config.json（MIT）。

美术素材按 CC BY-NC 4.0 授权（见 LICENSE.md）：须注明「克劳德大小姐 · Claude-girl」和仓库地址，不得商用。克劳德大小姐的形象由百度贴吧社区共创。
EOF
  rm -rf "characters/$id"
  mv "$out" "characters/$id"
done

echo "完成：characters/（$(du -sh "$ROOT/characters" | cut -f1)）：$(ls -d "$ROOT"/characters/*/ | xargs -n1 basename | tr '\n' ' ')"
