#!/bin/bash
# 画「用代码画的形象」：looks/drawn/rig.js 里本项目原创的三位大小姐（金卷 / 黑蔷薇 / 紫藤），
# 用 scripts/draw-look.swift（macOS 自带的 WebKit）渲染成立绘和动画精灵图，放到 characters/<id>/，再放上 looks/<id>/character.json。
# 只在画法、设定或渲染脚本改过时重画（按它们的哈希判断），build.sh 每次都会调用。
# 要 cwebp（brew install webp）才有动画；没装就只出静态立绘。
# 用法：./scripts/draw-looks.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
LOOKS="ojou-gold ojou-noir ojou-lilac"
FORCE="${1:-}"
BIN=build/draw-look
webp=""; command -v cwebp >/dev/null && webp="webp"

todo=""
for id in $LOOKS; do
  hash="$(cat looks/drawn/rig.js "looks/$id/character.json" scripts/draw-look.swift scripts/look-frames.py | shasum | cut -d' ' -f1)$webp"
  if [ "$FORCE" = "--force" ] || [ "$(cat "characters/$id/.drawn" 2>/dev/null)" != "$hash" ]; then todo="$todo $id:$hash"; fi
done
[ -z "$todo" ] && exit 0

mkdir -p build characters
if [ ! -x "$BIN" ] || [ scripts/draw-look.swift -nt "$BIN" ]; then
  echo "编译形象渲染器…"
  swiftc -O scripts/draw-look.swift -o "$BIN"
fi
[ -n "$webp" ] || echo "没装 cwebp（brew install webp）：大小姐们只有静态立绘，没有动画"
for item in $todo; do
  id="${item%%:*}"; hash="${item#*:}"
  echo "画 ${id}…"
  out="build/drawn-$id"
  rm -rf "$out"
  "$BIN" looks/drawn/rig.js "$id" "$out" >/dev/null
  # character.json：本项目写的设定和台词，加上每张精灵图实际几帧
  python3 -I scripts/look-frames.py "looks/$id/character.json" "$out/frames.json" "$out/character.json"
  rm "$out/frames.json"
  cat > "$out/SOURCE.md" <<EOT
# $id

本项目原创：立绘和动画由 \`scripts/draw-look.swift\` 按 \`looks/drawn/rig.js\`（用代码写的 SVG 矢量画法）渲染，
\`character.json\`（姿态对应、台词）来自 \`looks/$id/character.json\`。随代码按仓库 LICENSE 授权。
EOT
  echo "$hash" > "$out/.drawn"
  rm -rf "characters/$id"
  mv "$out" "characters/$id"
done
