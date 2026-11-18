#!/bin/bash
# 打包并安装到 ~/Applications/claudia-pet.app，然后打开她。
# 接入：装好后在菜单栏图标（或右键她）→「接入 AI 助手」→「Claude Code 插件」/「Codex hooks」/「Grok Build hooks」。
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
DEST="$HOME/Applications/claudia-pet.app"
mkdir -p "$HOME/Applications"
pkill -x claudia-pet 2>/dev/null || true
rm -rf "$DEST"
cp -R dist/claudia-pet.app "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
open "$DEST"
echo "已安装：$DEST"
echo "下一步：菜单栏图标 →「接入 AI 助手」→ 勾上「Claude Code 插件」「Codex hooks」「Grok Build hooks」里要用的（Codex 还要在 /hooks 里信任一次）。"
