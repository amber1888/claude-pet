# 来源与授权

本项目是 [claudia-pet](https://github.com/kirito1207/claudia-pet)（kirito1207，Windows 版）的 macOS 移植。非官方同人项目，与 Anthropic 无关。

## 代码

| 内容 | 来源 | 授权 |
|---|---|---|
| `mac/`（Swift 外壳）、`scripts/`、`docs/looks/`、`looks/` 中的代码与配置 | 本项目新写，参照 claudia-pet 的 C# 外壳逻辑 | 见仓库 [LICENSE](LICENSE) |
| 金卷 / 黑蔷薇 / 紫藤三位大小姐的设定和台词（`looks/ojou-*/character.json`） | 本项目原创 | 见仓库 [LICENSE](LICENSE)；她们的立绘见下一节 |
| `web/`（网页画面：动画、物理、台词、情绪） | 原样取自 claudia-pet（提交见 `upstream/claudia-pet-COMMIT`），它基于 [CrossPet](https://github.com/lokicorvus/crosspet)（lokicorvus），`web/dsh-physics.js` 摘录自 [dsh-pet](https://github.com/PC2005-cloud/dsh-pet)（PC2005-cloud） | MIT，许可全文见 `upstream/claudia-pet-LICENSE`、`upstream/CrossPet-LICENSE`，dsh-pet 的 MIT 许可见 `upstream/claudia-pet-NOTICE.md` 末尾 |
| `plugin/hooks/register.ts`（Claude Code 插件） | 移植自 claudia-pet 的插件（改自 CrossPet 的 Claude Code mod），只改了 macOS 路径和拉起方式 | MIT |

## 随仓库发布的立绘

金卷、黑蔷薇和紫藤三位大小姐的 30 张 PNG 原图位于 `looks/ojou-gold-art/`、`looks/ojou-noir-art/` 和 `looks/ojou-lilac-art/`。本项目依据服装与姿态提示词使用 ImageGen 重绘，画风及姿态参考 [claudia-pet](https://github.com/kirito1207/claudia-pet)（kirito1207）和 [CrossPet](https://github.com/lokicorvus/crosspet)（lokicorvus）的立绘。原 Claude 娘设定来自社区，作者未能确认。[大小姐提示词](docs/looks/大小姐提示词.md) · [上游来源说明](upstream/claudia-pet-NOTICE.md)

这些 PNG 沿用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh-hans)，须署名、不得商用，改编后按同一协议分享。

## 构建时拉取的角色素材

角色立绘、动画精灵图、台词（`characters/`）和图标（`assets/AppIcon.png`）由 `scripts/fetch-assets.sh` 从 claudia-pet、CrossPet 和 Claude-girl 的固定提交拉取，打包进 `.app` 一起分发时须遵守它们的授权：

- 立绘、设定、台词：CrossPet v1.3.8 及 claudia-pet 的衍生图，**CC BY-NC-SA 4.0**
- 「圣女」形象（`characters/claude-saint/`）：原样取自 CrossPet 的 `characters/claude-saint`（提交见 `upstream/crosspet-COMMIT`），**CC BY-NC-SA 4.0**；没有台词的场合沿用 claudia 的台词
- 「睡衣」形象（`characters/claude-pajamas/`）：图片原样取自 CrossPet 的彩蛋 `characters/egg-claude-pajamas`（同一提交），按 `looks/claude-pajamas/poses.txt` 换了文件名当作各个姿态；`looks/claude-pajamas/character.json` 里的台词是本项目写的（部分改写自原彩蛋台词），**CC BY-NC-SA 4.0**
- 动画动作（`characters/claude/anim/`）：hunmer 的 claude-pet 动作包（[hunmer/aboutme-pets](https://github.com/hunmer/aboutme-pets)），作者书面授权按 **CC BY-NC-SA 4.0** 在 claudia-pet 中使用
- 图标：claudia-pet 以 CrossPet 素材为参考制作，**CC BY-NC-SA 4.0**
- 「茶会大小姐」形象（`characters/claude-girl/`）：动画来自 [克劳德大小姐 · Claude-girl](https://github.com/wangxianda941030/Claude-girl)（wangxianda941030）的 `clips/`（提交见 `upstream/claude-girl-COMMIT`），**CC BY-NC 4.0**，须注明「克劳德大小姐 · Claude-girl」和仓库地址、不得商用；克劳德大小姐的形象由百度贴吧社区共创。本项目用 `scripts/video-look.sh` 按 `looks/claude-girl/video.txt` 转成精灵图和静态立绘；`looks/claude-girl/character.json` 是本项目写的，部分台词取自 Claude-girl 的 `pet-config.json`（MIT）

CC BY-NC-SA 4.0 要求：署名、**不得商用**、改编后按同一协议发布。详细来源见拉取后的 `characters/LICENSE.md`、`characters/README.md`、`characters/claude-saint/SOURCE.md`、`characters/claude-pajamas/SOURCE.md`、`characters/claude-girl/SOURCE.md` 和 `upstream/claudia-pet-NOTICE.md`。

## 商标

「Claude」是 Anthropic 的商标，Clawd 形象的相关权利归 Anthropic 所有。本项目只用这些名称和形象来指代、致敬对应产品，不表示获得 Anthropic、claudia-pet、CrossPet、Claude-girl 或 dsh-pet 作者的背书。
