#!/bin/bash
# 本项目的三位大小姐（金卷 / 黑蔷薇 / 紫藤）：把 looks/<id>-art/ 里生图得到的原图，用 scripts/prepare-look.swift
# 整理成桌宠的立绘规格（裁空白、脚踩底边、640 高、存 WebP），放到 characters/<id>/，再放上 looks/<id>/character.json（设定和台词）。
# build.sh 每次都会调用；原图、设定或脚本改过才重做（按它们的哈希判断）。
# 用法：./scripts/art-looks.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
LOOKS="ojou-gold ojou-noir ojou-lilac"
# 只画了 10 个姿态，别的先拿意思相近的一张顶上（只是复制一份换个文件名）：<姿态>:<用哪张>
# 不在这里的姿态由网页自己顺着替补找（busy_left → thinking、bye → happy……），最后用 idle。
EXTRA="proud:happy pat:happy surprised:listening
       pout:oops annoyed:oops puffed:oops sulk:oops sorry:oops
       searching:reading delegating:running
       hum:idle-blink tired:idle-blink sleeping:idle-blink"
FORCE="${1:-}"
BIN=build/prepare-look
webp=""; command -v cwebp >/dev/null && webp="webp"

todo=""
for id in $LOOKS; do
  hash="$( (cat "looks/$id/character.json" scripts/prepare-look.swift scripts/art-looks.sh; for f in "looks/$id-art"/*; do echo "$f"; done; cat "looks/$id-art"/*) | shasum | cut -d' ' -f1)$webp"
  if [ "$FORCE" = "--force" ] || [ "$(cat "characters/$id/.art" 2>/dev/null)" != "$hash" ]; then todo="$todo $id:$hash"; fi
done
[ -z "$todo" ] && exit 0

mkdir -p build characters
if [ ! -x "$BIN" ] || [ scripts/prepare-look.swift -nt "$BIN" ]; then
  echo "编译立绘整理工具…"
  swiftc -O scripts/prepare-look.swift -o "$BIN"
fi
[ -n "$webp" ] || echo "没装 cwebp（brew install webp）：大小姐们的立绘存成 PNG，体积大一些"
for item in $todo; do
  id="${item%%:*}"; hash="${item#*:}"
  echo "整理 ${id} 的立绘…"
  out="build/art-$id"
  rm -rf "$out"
  # 只显示提醒（背景没去干净、眨眼图尺寸不对之类），正常的进度不打印
  "$BIN" "looks/$id-art" "$id" --out "$out" | { grep -E '⚠️|跳过' || true; }
  ls "$out"/idle.* >/dev/null 2>&1 || { echo "  ${id}：没整理出 idle，跳过"; continue; }
  for pair in $EXTRA; do
    pose="${pair%%:*}"; from="${pair#*:}"
    if compgen -G "$out/$pose.*" >/dev/null || compgen -G "$out/$pose-*" >/dev/null; then continue; fi   # 画了的不顶替
    for f in "$out/$from".webp "$out/$from".png; do if [ -f "$f" ]; then cp "$f" "$out/$pose.${f##*.}"; fi; done
  done
  cp "looks/$id/character.json" "$out/character.json"
  cat > "$out/SOURCE.md" <<EOT
# $id

立绘来自本仓库 \`looks/$id-art/\`：本项目按 \`docs/looks/大小姐提示词.md\` 用 AI 生图工具画的，
画风和姿态参考 claudia-pet（kirito1207）、CrossPet（lokicorvus）的立绘，按 **CC BY-NC-SA 4.0** 授权（署名、不得商用、按同一协议分享），见仓库 NOTICE.md。
\`scripts/art-looks.sh\` 用 \`scripts/prepare-look.swift\` 裁剪、缩放、转 WebP；没画的姿态复制意思相近的一张顶上（见脚本里的 EXTRA）。
\`character.json\`（设定和台词）来自 \`looks/$id/character.json\`，是本项目写的。
EOT
  echo "$hash" > "$out/.art"
  rm -rf "characters/$id"
  mv "$out" "characters/$id"
done
