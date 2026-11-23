# claude-pet（macOS 版 claudia）

Claude 大小姐 **claudia** 的 macOS 桌宠：待在桌面上，跟着 Claude Code / Codex / Grok 的工作状态做动作，显示额度，能摸、能拖、能扔。

参照 [kirito1207/claudia-pet](https://github.com/kirito1207/claudia-pet)（Windows 版）实现：动画、物理、台词、情绪这些都在网页层（`web/`，原样沿用），本项目用 Swift + WKWebView 重写了 macOS 外壳，并把 Claude Code 插件移植到 macOS。非官方同人项目，与 Anthropic 无关。

## 安装

只需要 Xcode Command Line Tools（`xcode-select --install`），macOS 13 及以上。想要「茶会大小姐」形象的话再装 `brew install ffmpeg webp`（要把它的 WebM 动画转成精灵图；没装就跳过这一套，别的照常）。

```bash
./scripts/install.sh      # 拉素材 → 打包 → 装到 ~/Applications/claudia-pet.app → 打开
```

然后在菜单栏的 claudia 图标（或右键她）→「接入 AI 助手」：

- **Claude Code 插件**：把插件目录加进 `~/.claude/settings.json` 的 `env.CLAUDE_CODE_PLUGIN_DIRS`（改之前自动备份），新开的 Claude Code 会话生效。
- **Codex hooks**：往 `~/.codex/hooks.json`（有 `CODEX_HOME` 就用它）合并几条 hook，命令是 `~/.claudia/bin/claudia-hook --hook codex`（软链到程序本身，挪了程序也不用重配）。改之前自动备份，只增删自己的条目。**之后要在 Codex 里输入 `/hooks` 信任一次**，新开的会话生效。
- **Grok Build hooks**：写一个只归自己的文件 `~/.grok/hooks/claudia-pet.json`（有 `GROK_HOME` 就用它），命令是 `~/.claudia/bin/claudia-hook --hook grok`；撤销就是删掉这个文件。用户目录的 hooks 不用信任，新开的 grok 会话生效。

几家可以同时接：她演最近有动静的那家，几个会话（不分哪家）同时干活时一起出卡片。额度默认显示最近在用的那家，也可以在「接入 AI 助手 → 额度显示哪一家」里固定。

只想打包不安装：`./scripts/build.sh`，产物在 `dist/claudia-pet.app`。

## 她会做什么

- **跟着 Claude Code / Codex / Grok 干活**：你发消息时听你说，之后思考、看书（读文件 / 搜索）、写东西（改文件）、敲命令、查资料（上网）、派活（子代理）、整理记忆（压缩上下文）、有事问你（等授权或回答）；完成时开心（工具用得多时得意），出错哎呀，被打断吃惊。好几个会话同时干活时身边会出现每个会话的小卡片。
- **换形象**：「外观 → 形象」里换衣服，冒一下烟换上，手上的活、额度接着显示。自带默认、「圣女」「睡衣」（来自 CrossPet；睡衣只有 5 张图，干活时多半是待机的样子）和「茶会大小姐」（来自 [克劳德大小姐 · Claude-girl](https://github.com/wangxianda941030/Claude-girl)，整套都是动画：托腮思考、敲小键盘、翻书、双手合十等你、捧茶、想太久冒烟……），还有本项目的三位大小姐（照 [大小姐提示词](docs/looks/大小姐提示词.md) 生图画的立绘，每位 10 个姿态，没有动画）：**金卷大小姐**（金色螺旋卷、粉色蓬蓬裙、折扇，「哦～呵呵呵」）、**黑蔷薇大小姐**（黑长直、小礼帽、哥特裙、阳伞，嘴硬心软）、**紫藤大小姐**（浅紫长卷发、编发小银冠、紫裙白围裙、端着红茶，温温柔柔）——干活时托腮、翻书、执笔、指挥（金卷拿扇子点、黑蔷薇拿伞指、紫藤端茶），完成时笑眯了眼，出错了「><」，每位都有自己的台词。也可以自己加（见下）。
- **显示额度**：名牌下面显示 5 小时 / 每周已用额度，可选文字或额度条。
- **站在输入框上**：你在终端里给 Claude（Codex、Grok 也算）发消息，她就跳到那个终端窗口的输入框旁边陪着你，窗口挪她跟着挪。她有两个站的地方——**输入框上面**（轮到你说话时）和**输入框下面**（窗口底边，Claude 干活时），按会话上下跳：你发消息她从输入框上跳下去（把话带给 Claude）；干活时在下面隔一会儿蹦到另一处，或者跳上输入框探个头、一两秒后再跳下去；等你授权 / 回答时跳上来连蹦两下，没理她过几秒再蹦；完成从下面高高跳上输入框（干了一大票上去后再跳一下）；出错往后一个趔趄。右键菜单「跳上输入框 / 跳到输入框下面」也能叫她换（待 30 秒，有新动静再按会话来）。终端被盖住（同一块屏幕上切到别的程序）她跳回原来的位置，你转去另一块屏幕干活她就在这边接着站着；**多块屏幕**时她只待在自己那块屏幕上，终端在别的屏幕上她不跳过去，来回切屏她也不会满屏飞（想让她去那边，把她拖过去就行，拖到那边终端的输入框上也行）；把她从输入框上拖走，下次发消息前不再跳回去。**站得准**：打开「互动 → 精确对准输入框」并在「系统设置 → 隐私与安全性 → 屏幕与系统录音」里给 claudia-pet 权限（再重开她），她会隔几秒截一下那个终端窗口（只截那一个窗口，不存、不传），找 Claude Code 输入框上下那两条横线，脚正好踩在上边线上，左右只在终端那一栏里蹦，输入框变高了她也跟着挪（重新安装后 macOS 可能要你再勾一次权限）。没给权限时按 Claude Code 的布局估：上面一层在窗口底边往上 58 点、下面一层 6 点，对不上就**把她拖到那一层放下**，她会记住这种终端的位置（放得高算上面，低算下面）；这时只读窗口位置，不要任何权限。「互动 → 站在 Claude Code 输入框上」可以关掉。
- **邮件提醒**：直接连你的邮箱（IMAP），每分钟看一次收件箱。重要的新邮件用一个信纸样式的气泡念出发件人和主题，名牌旁边的小胶囊「✉ 4 · 王总」一直显示未读数和最新的重要发件人；点胶囊或气泡打开 Foxmail（没装就开网页邮箱）。见下面「邮件提醒」。
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

### Grok 的几点不同

- 读文件、搜代码、改文件、上网、派子代理都有自己的工具，直接对上动作；跑命令时和 Codex 一样按命令判断是「看书」还是「敲命令」。
- 出错、被打断、限流都有单独的事件：命令退出码不是 0 或工具失败算出错；你按 Ctrl+C、拒绝授权算被打断（吃惊），它自己放弃（回合数用完等）算出错。
- **本机看不到剩余额度**：额度那行显示这个会话花了多少钱和上下文用了多少（`本次会话 $0.05 · 上下文 36%`，读 `~/.grok/sessions/…/usage.json`、`signals.json`），不显示额度条和钱袋动画。被限流时这行变红、她累倒，下一轮正常做完就恢复。
- 不能把 hook 写进 `~/.claude/settings.json`：grok 也读那里的 hooks，会和 Claude Code 各收一份。

## 邮件提醒

菜单「邮件提醒 → 添加邮箱…」：填邮箱地址和**授权码**（不是登录密码），类型一般按后缀自动认出。

| 邮箱 | 去哪开 IMAP、拿授权码 |
|---|---|
| QQ 邮箱 / foxmail.com | 网页版 设置 → 账号 → 开启「IMAP/SMTP 服务」，生成授权码 |
| 腾讯企业邮 | 网页版 设置 → 客户端设置 → 开启 IMAP；开了安全登录的要生成客户端专用密码 |
| 网易 163 / 126 / yeah.net | 网页版 设置 → POP3/SMTP/IMAP → 开启 IMAP，新增授权密码 |
| Gmail / iCloud | 应用专用密码（要先开两步验证） |
| 其他 | 「类型」选其他，填 IMAP 服务器（`imap.example.com` 或 `imap.example.com:993`） |

- **只读**：用 `EXAMINE` 打开收件箱、`BODY.PEEK` 只取发件人和主题，不会把邮件标成已读，不下载正文。在 Foxmail 或手机上读过，胶囊上的数字跟着减。
- **重要邮件**：「邮件提醒 → 重要邮件…」填发件人或主题里的词（如 `boss@company.com, 合同, 发票`）。命中的她会念出来、发系统通知；其他的只让名牌旁的胶囊跳一下、数字加一。不填就每封都念。
- 第一次连上时已有的未读只算数、不念；之后新来的才念。重启程序不会重念。
- 授权码存在系统钥匙串（服务名 `local.claudia-pet.mail`），设置里只存邮箱地址和服务器。重新打包（签名变了）后第一次读取钥匙串，macOS 可能会问一次是否允许，点「始终允许」。
- 网络断了自己重连；授权码不对会停下来不再反复登录（免得邮箱被锁），改了授权码或点「现在检查」再试。
- Outlook / Hotmail 个人邮箱已经不支持用密码登录 IMAP，暂时接不了。

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
web/              网页画面（取自 claudia-pet；mail.js 是本项目加的邮件胶囊和念邮件的气泡）
plugin/           Claude Code 插件（写 ~/.claudia/state/claude-*.json，会话开始时用 open 拉起桌宠）
                  Codex / Grok 没有单独的插件：程序自己就是 hook（mac/Sources/Hooks.swift 共用部分，
                  Codex.swift、Grok.swift 各自的事件对应，写 codex-*.json / grok-*.json）
scripts/          fetch-assets.sh 拉素材 / build.sh 打包 / install.sh 安装 / prepare-look.swift 整理新衣服立绘 /
                  video-look.sh 把带透明通道的 WebM 动画转成形象（精灵图 + 静态立绘） /
                  art-looks.sh 把仓库里大小姐们的原图整理成立绘（build.sh 自动调用）
docs/looks/       做新衣服：流程和生图提示词
looks/            各形象的设置台词（character.json）；用别人的图拼出来的形象还有怎么拼（poses.txt）；
                  ojou-*-art/ 是三位大小姐的原图（PNG，CC BY-NC-SA 4.0）
upstream/         上游的许可、来源说明和固定的提交号
```

开发自检：设置 `CLAUDIA_DEBUG_DIR=<目录>` 直接运行 `dist/claudia-pet.app/Contents/MacOS/claudia-pet`，往 `<目录>/cmd.js` 写一段脚本就会在网页里执行，结果写到 `out.txt`、画面截到 `snap.png`；写 `#throw` 模拟一次抛掷，写 `#codex install` / `#codex uninstall`（`#grok …` 同理）不弹窗地接入 / 撤销 Codex / Grok，写 `#perch fake <x> <y> <宽> <高>` / `#perch box <上> <下> <左> <右>` / `#perch nobox` / `#perch screens <x> <y> <宽> <高> …` / `#perch drop <x> <y>` / `#perch off` / `#perch status` 假装终端窗口在那（锁屏时测「站在输入框上」），写 `#look <形象 id>` / `#look rescan` 换形象 / 重新扫描，写 `#mail status` / `#mail check` / `#mail keychain` 看邮件提醒的状态、立刻检查、自检钥匙串（调试时可以用 `CLAUDIA_MAIL_TEST_PASSWORD` 代替钥匙串里的授权码）。模拟 Codex 事件：`echo '{"session_id":"s","hook_event_name":"UserPromptSubmit"}' | CLAUDIA_STATE_DIR=<目录> dist/claudia-pet.app/Contents/MacOS/claudia-pet --hook codex`（`--hook grok` 同理）。

## 授权

见 [NOTICE.md](NOTICE.md)。代码见 [LICENSE](LICENSE)，沿用的上游代码为 MIT；角色立绘、动画和图标不在仓库里（由脚本拉取），按 **CC BY-NC-SA 4.0** 授权，**不得商用**。
