#!/bin/bash
# 打包 dist/claudia-pet.app：编译 Swift 外壳，带上网页、角色素材、Claude Code 插件和图标。
# 只需要 Xcode Command Line Tools（swiftc、iconutil、codesign），不需要 Xcode。
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="$ROOT/dist/claudia-pet.app"
BUILD="$ROOT/build"

[ -f characters/claude/character.json ] || ./scripts/fetch-assets.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

# 默认只编本机架构；要通用版：ARCHS="arm64 x86_64" ./scripts/build.sh
ARCHS="${ARCHS:-$(uname -m)}"
echo "编译 Swift（${ARCHS}）…"
for arch in $ARCHS; do
  swiftc -O -target "$arch-apple-macos13.0" -module-name ClaudiaPet \
    -framework AppKit -framework WebKit -framework Carbon -framework ServiceManagement -framework UserNotifications -framework Network -framework Security -framework ScreenCaptureKit \
    mac/Sources/*.swift -o "$BUILD/claudia-pet-$arch"
done
lipo -create $(for arch in $ARCHS; do echo "$BUILD/claudia-pet-$arch"; done) -output "$APP/Contents/MacOS/claudia-pet"

sed "s/__VERSION__/$VERSION/g" mac/Info.plist > "$APP/Contents/Info.plist"
R="$APP/Contents/Resources"
cp -R web "$R/web"
cp -R characters "$R/characters"
cp -R plugin "$R/plugin"
cp VERSION "$R/VERSION"
cp assets/AppIcon.png "$R/AppIcon.png"
cp LICENSE NOTICE.md "$R/"
mkdir -p "$R/upstream" && cp upstream/* "$R/upstream/"

echo "生成图标…"
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) assets/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$R/AppIcon.icns"

echo "签名（ad-hoc）…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "完成：$APP"
