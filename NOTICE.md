# 来源与授权

本项目是 [claudia-pet](https://github.com/kirito1207/claudia-pet)（kirito1207，Windows 版）的 macOS 移植。非官方同人项目，与 Anthropic 无关。

## 代码

| 内容 | 来源 | 授权 |
|---|---|---|
| `mac/`（Swift 外壳）、`scripts/`、`docs/looks/`、`looks/` | 本项目新写，参照 claudia-pet 的 C# 外壳逻辑 | 见仓库 [LICENSE](LICENSE) |
| `web/`（网页画面：动画、物理、台词、情绪） | 原样取自 claudia-pet（提交见 `upstream/claudia-pet-COMMIT`），它基于 [CrossPet](https://github.com/lokicorvus/crosspet)（lokicorvus），`web/dsh-physics.js` 摘录自 [dsh-pet](https://github.com/PC2005-cloud/dsh-pet)（PC2005-cloud） | MIT，许可全文见 `upstream/claudia-pet-LICENSE`、`upstream/CrossPet-LICENSE`，dsh-pet 的 MIT 许可见 `upstream/claudia-pet-NOTICE.md` 末尾 |
| `plugin/hooks/register.ts`（Claude Code 插件） | 移植自 claudia-pet 的插件（改自 CrossPet 的 Claude Code mod），只改了 macOS 路径和拉起方式 | MIT |

## 角色素材（不在本仓库里）

角色立绘、动画精灵图、台词（`characters/`）和图标（`assets/AppIcon.png`）由 `scripts/fetch-assets.sh` 从 claudia-pet 和 CrossPet 的固定提交拉取，打包进 `.app` 一起分发时须遵守它们的授权：

- 立绘、设定、台词：CrossPet v1.3.8 及 claudia-pet 的衍生图，**CC BY-NC-SA 4.0**
- 「圣女」形象（`characters/claude-saint/`）：原样取自 CrossPet 的 `characters/claude-saint`（提交见 `upstream/crosspet-COMMIT`），**CC BY-NC-SA 4.0**；没有台词的场合沿用 claudia 的台词
- 「睡衣」形象（`characters/claude-pajamas/`）：图片原样取自 CrossPet 的彩蛋 `characters/egg-claude-pajamas`（同一提交），按 `looks/claude-pajamas/poses.txt` 换了文件名当作各个姿态；`looks/claude-pajamas/character.json` 里的台词是本项目写的（部分改写自原彩蛋台词），**CC BY-NC-SA 4.0**
- 动画动作（`characters/claude/anim/`）：hunmer 的 claude-pet 动作包（[hunmer/aboutme-pets](https://github.com/hunmer/aboutme-pets)），作者书面授权按 **CC BY-NC-SA 4.0** 在 claudia-pet 中使用
- 图标：claudia-pet 以 CrossPet 素材为参考制作，**CC BY-NC-SA 4.0**

CC BY-NC-SA 4.0 要求：署名、**不得商用**、改编后按同一协议发布。详细来源见拉取后的 `characters/LICENSE.md`、`characters/README.md`、`characters/claude-saint/SOURCE.md`、`characters/claude-pajamas/SOURCE.md` 和 `upstream/claudia-pet-NOTICE.md`。

## 商标

「Claude」是 Anthropic 的商标，Clawd 形象的相关权利归 Anthropic 所有。本项目只用这些名称和形象来指代、致敬对应产品，不表示获得 Anthropic、claudia-pet、CrossPet 或 dsh-pet 作者的背书。
