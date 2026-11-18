# 给 claudia 做一套新衣服

流程：**写衣服描述 → 先画待机图 → 照着待机图画其他姿态 → 跑对齐脚本 → 桌宠里重新扫描**。

提示词在 [提示词.md](提示词.md)。做法沿用 claudia-pet 上游补图的方法（上游用 AI 生图工具按设计参考重画立绘，见其 `docs/prompts/`）。

## 1. 准备

- 先运行一次 `./scripts/fetch-assets.sh`，参考图都在拉下来的 `characters/` 里。
- 生图工具要能**上传参考图**、最好能**直接出透明背景**（比如 OpenAI 的图像生成打开 `transparent_background`）。不能出透明的，生成时要求纯白背景，对齐时加 `--white-bg`（只能抠掉外围白底，头发缝隙里的白色抠不掉，效果不如真透明）。
- 新建一个文件夹放原图，比如 `~/Downloads/maid/`。**文件名就是姿态名**（下表），同一姿态多画一张叫 `happy-2.png`，会随机轮换。

## 2. 画哪些

先画「必画」的 10 张就能用；没画的姿态会顺着替补找相近的（比如没有 `proud` 用 `happy`），最后用 `idle`。

| 姿态 | 什么时候出现 | 级别 | 姿势参考图 |
|---|---|---|---|
| `idle` | 待机。**第一张画它**，后面每张都拿它当衣服参考 | 必画 | `characters/claude/idle.webp` |
| `idle-blink` | 待机眨眼帧：**拿你画好的 idle 改图**，只把眼睛改成闭眼，别的一个像素都别动 | 必画 | 你的 `idle.png` |
| `listening` | 你刚发消息 | 必画 | `characters/claude/listening.webp` |
| `thinking` | 思考 | 必画 | `characters/claude-saint/thinking.webp` |
| `reading` | 读文件、搜代码 | 必画 | `characters/claude/reading.webp` |
| `writing` | 改文件 | 必画 | `characters/claude-saint/writing.webp` |
| `running` | 跑命令 | 必画 | `characters/claude-saint/running.webp` |
| `happy` | 一轮做完 | 必画 | `characters/claude-saint/happy.webp` |
| `oops` | 出错 | 必画 | `characters/claude/oops.webp` |
| `asking` | 等你授权 / 回答 | 必画 | `characters/claude/asking.webp` |
| `searching` | 上网查资料 | 建议 | `characters/claude/searching.webp` |
| `delegating` | 派子代理干活 | 建议 | `characters/claude/delegating.webp` |
| `proud` | 大活做完（用了很多工具） | 建议 | `characters/claude/proud.webp` |
| `surprised` | 被打断 | 建议 | `characters/claude-saint/surprised.webp` |
| `pat` | 被摸头 | 建议 | `characters/claude-saint/pat.webp` |
| `sleeping` | 闲久了睡着（坐着 / 趴着） | 建议 | `characters/claude-saint/sleeping.webp` |
| `tired` | 额度快用完 | 建议 | `characters/claude/tired.webp` |
| `sorry` | 出错后你又发消息（认错） | 建议 | `characters/claude/sorry.webp` |
| `compact` | 整理上下文 | 建议 | `characters/claude-saint/compact.webp` |
| `busy_left` / `busy_right` | 几个会话同时干活，轮流看左右（**不要镜像翻转**，发饰位置会反） | 建议 | `characters/claude/busy_left.webp` / `busy_right.webp` |
| `hum` `stretch` `yawn` | 闲着时的小动作 | 可选 | `characters/claude-saint/` 同名 |
| `annoyed` `puffed` `redhot` `sulk` `coaxed` `forgiven` | 被来回晃时生气、被哄好 | 可选 | `characters/claude/` 同名 |
| `dizzy` `clawd` `swamped_left` `swamped_right` `bye` `update` | 晕、抱 Clawd、忙不过来、道别、拆礼物 | 可选 | `characters/claude/` 或 `characters/claude-saint/` 同名 |

## 3. 生图

每张：

1. 打开透明背景。
2. 上传参考图（顺序有讲究，见 [提示词.md](提示词.md) 的「附图」）：
   - 图 1：`characters/claude/idle.webp`（脸、发型、身体比例）
   - 图 2：这个姿态的参考图（上表最后一列，只看姿势和表情）
   - 图 3：你已经画好的 `idle.png`（画 idle 本身时不传）——**新衣服靠它保持每张一致**
3. 提示词 = 「通用部分」+「衣服」（选一套预设或自己写）+「这张的姿势」。
4. 存成 `<姿态名>.png` 放进原图文件夹。不满意就重画，人物画得大小不一没关系，脚本会统一。

小提示：

- **衣服描述写具体**：颜色、材质、领口、袖子、裙长、配饰，每张都贴同一段，换一个词衣服就会变。
- 发饰在**她的左侧（画面右侧）**，书是她的标志道具，换装也保留，认得出是 claudia。
- 画出来的手指、多余的特效字、地面阴影，重画比修图快。

## 4. 对齐

```bash
swift scripts/prepare-look.swift ~/Downloads/maid maid --name 女仆
```

- 第二个参数是形象 id（英文、数字、`-`、`_`），第三个 `--name` 是菜单里显示的名字。
- 输出到 `~/.claudia/characters/<id>/`：每张裁掉空白，缩放到和自带立绘一样大（640 高的画布，站着的人物 638 高），脚踩底边、左右居中；坐着躺着的（`sleeping`、`tired` 等）按 idle 的倍数缩放，头的大小和站着时一致；`idle-blink` 完全照 idle 摆放。
- 没有 `character.json` 就写一份最简的；已有就不动。
- 装了 `cwebp`（`brew install webp`）会存成 WebP，否则存 PNG（大一些，都能用）。
- 跑完会列出还缺哪些姿态。补画后放进原图文件夹再跑一遍就行（已有的会覆盖）。
- 坐姿有别的名字时用 `--sit 姿态,姿态` 指定。

## 5. 用上

桌宠菜单「外观 → 形象 → 重新扫描形象」，再选新衣服。

## 6. 换台词（可选）

不写台词就用 claudia 的。想让这套衣服说不一样的话，在 `character.json` 里加 `lines`，只写想换的，没写的照旧：

```json
{
  "skinOf": "claude",
  "skinName": "女仆",
  "greeting": "欢迎回来，主人……不对，是欢迎回来。",
  "lines": {
    "idle": ["随时听候吩咐。", "茶已经泡好了。"],
    "happy": ["打扫完毕～", "请过目。"],
    "oops": ["啊，打翻了……我马上收拾。"]
  }
}
```

姿态名就是 `lines` 的键，完整列表见 `characters/claude/character.json`。

## 已有的动画素材

素材是带透明通道的 WebM 动画（比如 [Claude-girl](https://github.com/wangxianda941030/Claude-girl) 的 `clips/`）时不用重画，用 `scripts/video-look.sh` 直接转：写一个说明文件（格式见脚本开头，例子是 `looks/claude-girl/video.txt`）——用哪段校准大小、每张精灵图用哪几段、静态立绘取哪一帧——再跑

```bash
scripts/video-look.sh <片段目录> ~/.claudia/characters/<id> <说明文件>
python3 scripts/look-frames.py <你的 character.json> ~/.claudia/characters/<id>/frames.json ~/.claudia/characters/<id>/character.json
```

要 `brew install ffmpeg webp`。macOS 的网页引擎播这种 WebM 会丢透明通道（人物外面一个黑框），所以一定要转。

## 授权

照着 claudia 的设计画的衣服是她的衍生作品：默认形象按 CC BY-NC-SA 4.0 授权，所以新衣服也要**署名（CrossPet、claudia-pet 及原设定作者）、不得商用、按同一协议分享**。自己用不受影响。
