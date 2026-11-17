# claude-pet（macOS 版 claudia）

Claude 大小姐 **claudia** 的 macOS 桌宠：待在桌面上，跟着 Claude Code 的工作状态做动作，显示额度，能摸、能拖、能扔。

参照 [kirito1207/claudia-pet](https://github.com/kirito1207/claudia-pet)（Windows 版）实现：动画、物理、台词、情绪这些都在网页层（`web/`，原样沿用），本项目用 Swift + WKWebView 重写了 macOS 外壳，并把 Claude Code 插件移植到 macOS。非官方同人项目，与 Anthropic 无关。

## 安装

只需要 Xcode Command Line Tools（`xcode-select --install`），macOS 13 及以上。

```bash
./scripts/install.sh      # 拉素材 → 打包 → 装到 ~/Applications/claudia-pet.app → 打开
```

然后在菜单栏的 claudia 图标（或右键她）→「接入 Claude」→ 勾上「Claude Code 插件」。这会把插件目录加进 `~/.claude/settings.json` 的 `env.CLAUDE_CODE_PLUGIN_DIRS`（改之前自动备份），新开的 Claude Code 会话生效。

只想打包不安装：`./scripts/build.sh`，产物在 `dist/claudia-pet.app`。

## 她会做什么

- **跟着 Claude Code 干活**：你发消息时听你说，之后思考、看书（读文件 / 搜索）、写东西（改文件）、敲命令、查资料（上网）、派活（子代理）、整理记忆（压缩上下文）、有事问你（等授权或回答）；完成时开心（工具用得多时得意），出错哎呀，被打断吃惊。好几个会话同时干活时身边会出现每个会话的小卡片。
- **显示额度**：名牌下面显示 5 小时 / 每周已用额度，可选文字或额度条。
- **任务通知**：一轮完成或出错、等你授权或回答时发系统通知（可设成只在终端 / Claude 不在前台时通知）。
- **会被摸、会生气**：单击摸头；按住来回晃会不耐烦、鼓脸、红温、赌气，要摸头哄回来。
- **可以拖、可以扔**：带弹性跟着鼠标，快速松手能扔出去，碰到屏幕边反弹，落地会滑一段，偶尔撞头、摔倒。
- **闲着也有事做**：哼歌、伸懒腰、抱 Clawd、各种小动作和才艺、按时段和节日打招呼，闲久了会睡着。
- 右键菜单（和菜单栏图标同一个）：摸摸头、戳一下、按分组点播全部动作、外观、互动、通知、接入 Claude、登录时自动启动、回到默认位置、暂时隐藏（`⌃⌥P`）、退出。

从菜单「退出」后，插件不会再自动把她叫出来，直到你自己再打开程序。

## 和 Windows 版的差别

- 只有「待在桌面上」：浮在所有窗口上面、所有桌面空间都在，活动范围是所在显示器的可用区域（不含菜单栏和程序坞）。还没做「待在 Claude 窗口里」、多开、桌面端 MCP 接入、设置窗口（设置都在右键菜单里）。
- 数据和状态目录与 Windows 版相同：`~/.claudia/`（状态在 `~/.claudia/state/`，日志 `~/.claudia/mac.log`）；设置存在 `local.claudia-pet.mac` 的偏好设置里。

## 目录

```
mac/Sources/      Swift 外壳：透明窗口、鼠标、拖拽 / 走路的窗口移动、读状态文件、菜单、通知、快捷键
web/              网页画面（原样取自 claudia-pet）
plugin/           Claude Code 插件（写 ~/.claudia/state/*.json，会话开始时用 open 拉起桌宠）
scripts/          fetch-assets.sh 拉素材 / build.sh 打包 / install.sh 安装
upstream/         上游的许可、来源说明和固定的提交号
```

开发自检：设置 `CLAUDIA_DEBUG_DIR=<目录>` 直接运行 `dist/claudia-pet.app/Contents/MacOS/claudia-pet`，往 `<目录>/cmd.js` 写一段脚本就会在网页里执行，结果写到 `out.txt`、画面截到 `snap.png`；写 `#throw` 模拟一次抛掷。

## 授权

见 [NOTICE.md](NOTICE.md)。代码见 [LICENSE](LICENSE)，沿用的上游代码为 MIT；角色立绘、动画和图标不在仓库里（由脚本拉取），按 **CC BY-NC-SA 4.0** 授权，**不得商用**。
