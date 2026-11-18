# claude-pet（macOS 版 claudia）

Claude 大小姐 **claudia** 的 macOS 桌宠：待在桌面上，跟着 Claude Code / Codex 的工作状态做动作，显示额度，能摸、能拖、能扔。

参照 [kirito1207/claudia-pet](https://github.com/kirito1207/claudia-pet)（Windows 版）实现：动画、物理、台词、情绪这些都在网页层（`web/`，原样沿用），本项目用 Swift + WKWebView 重写了 macOS 外壳，并把 Claude Code 插件移植到 macOS。非官方同人项目，与 Anthropic 无关。

## 安装

只需要 Xcode Command Line Tools（`xcode-select --install`），macOS 13 及以上。

```bash
./scripts/install.sh      # 拉素材 → 打包 → 装到 ~/Applications/claudia-pet.app → 打开
```

然后在菜单栏的 claudia 图标（或右键她）→「接入 AI 助手」：

- **Claude Code 插件**：把插件目录加进 `~/.claude/settings.json` 的 `env.CLAUDE_CODE_PLUGIN_DIRS`（改之前自动备份），新开的 Claude Code 会话生效。
- **Codex hooks**：往 `~/.codex/hooks.json`（有 `CODEX_HOME` 就用它）合并几条 hook，命令是 `~/.claudia/bin/claudia-hook --hook codex`（软链到程序本身，挪了程序也不用重配）。改之前自动备份，只增删自己的条目。**之后要在 Codex 里输入 `/hooks` 信任一次**，新开的会话生效。

两个可以同时接：她演最近有动静的那家，几个会话（不分哪家）同时干活时一起出卡片。额度默认显示最近在用的那家，也可以在「接入 AI 助手 → 额度显示哪一家」里固定。

只想打包不安装：`./scripts/build.sh`，产物在 `dist/claudia-pet.app`。

## 她会做什么

- **跟着 Claude Code / Codex 干活**：你发消息时听你说，之后思考、看书（读文件 / 搜索）、写东西（改文件）、敲命令、查资料（上网）、派活（子代理）、整理记忆（压缩上下文）、有事问你（等授权或回答）；完成时开心（工具用得多时得意），出错哎呀，被打断吃惊。好几个会话同时干活时身边会出现每个会话的小卡片。
- **换形象**：「外观 → 形象」里换衣服，冒一下烟换上，手上的活、额度接着显示。自带默认、「圣女」和「睡衣」三套（后两套来自 CrossPet；睡衣只有 5 张图，干活时多半是待机的样子），也可以自己加（见下）。
- **显示额度**：名牌下面显示 5 小时 / 每周已用额度，可选文字或额度条。
- **任务通知**：一轮完成或出错、等你授权或回答时发系统通知（可设成只在终端 / Claude 不在前台时通知）。
- **会被摸、会生气**：单击摸头；按住来回晃会不耐烦、鼓脸、红温、赌气，要摸头哄回来。
- **可以拖、可以扔**：带弹性跟着鼠标，快速松手能扔出去，碰到屏幕边反弹，落地会滑一段，偶尔撞头、摔倒。
- **闲着也有事做**：哼歌、伸懒腰、抱 Clawd、各种小动作和才艺、按时段和节日打招呼，闲久了会睡着。
- 右键菜单（和菜单栏图标同一个）：摸摸头、戳一下、按分组点播全部动作、外观（形象、大小……）、互动、通知、接入 AI 助手、登录时自动启动、回到默认位置、暂时隐藏（`⌃⌥P`）、退出。

从菜单「退出」后，插件 / hook 不会再自动把她叫出来，直到你自己再打开程序。

### Codex 的几点不同

- Codex 读文件、搜代码多半是跑命令：`cat`、`sed -n`、`rg`、`git diff` 这类算「看书」，`curl` 算「查资料」，其他算「敲命令」。
- Codex 内置的联网搜索不经过 hook，搜的时候她不会有反应。
- 「有事问你」只在 Codex 要你授权时出现（Codex 没有「停下来问你问题」的工具）。
- Codex 的 `Stop` 不带结束原因：这一轮最后一次模型请求失败才算出错。
- 额度从会话记录（`transcript_path`）里最后一条 `rate_limits` 读，会话开始和每轮结束时更新；用 API key 的话没有这项数据，就不显示。

## 自己加形象

「外观 → 形象 → 打开自定义形象文件夹…」打开 `~/.claudia/characters/`，在里面建一个文件夹（名字就是形象 id），放：

- `character.json`：最少写 `{"skinOf": "claude", "skinName": "菜单里显示的名字"}`。写了 `skinOf: "claude"` 就是 claudia 的一套衣服：名字跟着 claudia，没写的台词、设置都沿用她的；想换台词就写 `lines`（格式照 `characters/claude/character.json`）。
- 立绘：`idle.webp`（必须有）和各个姿态的图，文件名就是姿态名（`thinking.webp`、`writing.webp`、`happy.webp`……，`-2`、`-3` 是同一姿态的备选，`idle-blink.webp` 是眨眼帧），png 也行，尺寸比例照默认形象。没画的姿态会找相近的顶上（比如没有 `bonk` 就用 `surprised`），最后用 `idle`。
- 想要动画：照默认形象放 `anim/` 精灵图并在 `character.json` 里写 `animations`；不写就只用静态立绘（默认形象的动画画的是默认衣服，不会沿用）。

放好后点「重新扫描形象」。和自带形象同名的文件夹会被忽略。

**想用 AI 生图做一套新衣服**：[docs/looks/](docs/looks/README.md) 里有完整流程、每个姿态的生图提示词（带女仆装、学院制服、冬装、浴衣、睡衣五套衣服描述）和参考图对照表；画好后用对齐脚本一步整理成形象文件夹：

```bash
swift scripts/prepare-look.swift ~/Downloads/maid maid --name 女仆   # 原图文件夹、形象 id、菜单名
```

## 和 Windows 版的差别

- 只有「待在桌面上」：浮在所有窗口上面、所有桌面空间都在，活动范围是所在显示器的可用区域（不含菜单栏和程序坞）。还没做「待在 Claude 窗口里」、多开、桌面端 MCP 接入、设置窗口（设置都在右键菜单里）。
- 数据和状态目录与 Windows 版相同：`~/.claudia/`（状态在 `~/.claudia/state/`，日志 `~/.claudia/mac.log`）；设置存在 `local.claudia-pet.mac` 的偏好设置里。

## 目录

```
mac/Sources/      Swift 外壳：透明窗口、鼠标、拖拽 / 走路的窗口移动、读状态文件、菜单、通知、快捷键
web/              网页画面（原样取自 claudia-pet）
plugin/           Claude Code 插件（写 ~/.claudia/state/claude-*.json，会话开始时用 open 拉起桌宠）
                  Codex 没有单独的插件：mac/Sources/Codex.swift 就是 hook（写 codex-*.json）
scripts/          fetch-assets.sh 拉素材 / build.sh 打包 / install.sh 安装 / prepare-look.swift 整理新衣服立绘
docs/looks/       做新衣服：流程和生图提示词
looks/            用别人的图拼出来的形象：怎么拼（poses.txt）和本项目写的设置台词（character.json）
upstream/         上游的许可、来源说明和固定的提交号
```

开发自检：设置 `CLAUDIA_DEBUG_DIR=<目录>` 直接运行 `dist/claudia-pet.app/Contents/MacOS/claudia-pet`，往 `<目录>/cmd.js` 写一段脚本就会在网页里执行，结果写到 `out.txt`、画面截到 `snap.png`；写 `#throw` 模拟一次抛掷，写 `#codex install` / `#codex uninstall` 不弹窗地接入 / 撤销 Codex，写 `#look <形象 id>` / `#look rescan` 换形象 / 重新扫描。模拟 Codex 事件：`echo '{"session_id":"s","hook_event_name":"UserPromptSubmit"}' | CLAUDIA_STATE_DIR=<目录> dist/claudia-pet.app/Contents/MacOS/claudia-pet --hook codex`。

## 授权

见 [NOTICE.md](NOTICE.md)。代码见 [LICENSE](LICENSE)，沿用的上游代码为 MIT；角色立绘、动画和图标不在仓库里（由脚本拉取），按 **CC BY-NC-SA 4.0** 授权，**不得商用**。
