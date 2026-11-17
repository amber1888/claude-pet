import AppKit
import ServiceManagement

/// 带闭包的菜单项
final class ClosureItem: NSMenuItem {
    private let action_: () -> Void
    init(_ title: String, checked: Bool? = nil, key: String = "", _ action: @escaping () -> Void) {
        action_ = action
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        if let checked { state = checked ? .on : .off }
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { action_() }
}

extension NSMenu {
    @discardableResult func add(_ title: String, checked: Bool? = nil, _ action: @escaping () -> Void) -> NSMenuItem {
        let i = ClosureItem(title, checked: checked, action); addItem(i); return i
    }
    @discardableResult func sub(_ title: String, _ fill: (NSMenu) -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""), m = NSMenu(title: title)
        fill(m); i.submenu = m; addItem(i); return i
    }
    func sep() { addItem(.separator()) }
}

extension Pet {
    // 右键「动作 → 分组 → 具体动作」（同 Windows 版的分组和中文名）
    static let actionGroups: [(String, [String])] = [
        ("日常", ["idle", "hum", "stretch", "yawn", "sleeping", "clawd"]),
        ("工作", ["listening", "thinking", "reading", "searching", "writing", "running", "delegating", "compact", "busy_left", "busy_right", "swamped_left", "swamped_right", "asking", "sorry"]),
        ("心情", ["happy", "proud", "surprised", "oops", "annoyed", "puffed", "redhot", "sulk", "coaxed", "forgiven"]),
        ("互动", ["pat", "pout", "bye", "bonk", "stagger", "fallen", "faceplant", "dizzy"]),
        ("问候", ["greet_morning", "greet_noon", "greet_afternoon", "greet_evening", "greet_night"]),
        ("小动作", ["look", "tap", "cube", "bubbles", "pen_spin", "finger_count", "nails", "scratch", "eye_rub", "tummy", "toes", "leg_bounce", "hand_flick", "wrist_roll"]),
        ("Claude 梗", ["token", "mutter", "mutter_lazy", "abacus", "gamer"]),
        ("才艺", ["cards", "dove", "flower", "bookspirit", "animals", "butterflies", "juggle", "flute", "violin", "leaf_flute", "glass_harp", "air_guitar", "music_box", "woodfish", "dance_skirt", "dance_otaku", "dance_swing", "curtsy", "dressup"]),
        ("玩耍", ["toycar", "update", "watergun", "gomoku", "top", "cat", "shuttlecock", "rockinghorse", "pagebeat", "jenga", "dandelion", "forehead_flick", "bubble_wrap", "skip_stone", "diabolo", "hat_toss", "apple_toss", "dice", "cats_cradle", "shadow_step", "umbrella_spin", "plate_spin"]),
        ("手工", ["beads", "paper_boat", "clay", "ink", "grasshopper"]),
        ("吃喝", ["rice", "onigiri", "soup", "fishbone", "hotpot", "crab", "snack", "chocolate", "pudding", "cracker", "honey", "sweet_potato", "chestnut", "corn", "watermelon", "shaved_ice", "soda"]),
        ("节日", ["fest_newyear", "laba", "fest_spring", "fest_lantern", "qingtuan", "fest_dragonboat", "qixi", "zhongyuan", "fest_midautumn", "chongyang", "chongyanggao", "fest_halloween", "fest_christmas"]),
        ("四季", ["kite", "raindrop", "clear_umbrella", "windy", "sunshade", "fan", "cicada", "leaves", "hand_warmer", "warm_breath", "snowflake", "snow_step"]),
        ("走路", ["walk_crab", "walk_float", "run_left"]),
        ("余额", ["quota_full", "quota_jingle", "quota_count", "quota_empty", "quota_broke", "tired"]),
    ]
    static let actionNames: [String: String] = [
        "idle": "待机", "hum": "哼歌", "stretch": "伸懒腰", "yawn": "打哈欠", "tired": "累了", "sleeping": "睡觉", "clawd": "抱 Clawd",
        "listening": "听你说", "thinking": "思考", "reading": "看书", "writing": "写东西", "running": "敲命令", "searching": "查资料",
        "delegating": "派活", "compact": "整理记忆", "busy_left": "忙碌（左）", "busy_right": "忙碌（右）",
        "swamped_left": "忙不过来（左）", "swamped_right": "忙不过来（右）", "update": "拆礼物",
        "happy": "开心", "proud": "得意", "surprised": "吃惊", "oops": "哎呀", "sorry": "道歉", "asking": "有事问你",
        "annoyed": "不耐烦", "puffed": "鼓脸", "redhot": "红温", "sulk": "赌气", "coaxed": "被哄", "forgiven": "原谅你了", "dizzy": "晕乎乎",
        "pat": "被摸头", "pout": "傲娇", "bye": "再见", "bonk": "撞头", "stagger": "站不稳", "fallen": "摔倒", "faceplant": "趴地",
        "greet_morning": "早上好", "greet_noon": "中午好", "greet_afternoon": "下午好", "greet_evening": "晚上好", "greet_night": "晚安",
        "fest_newyear": "元旦迎新", "fest_spring": "春节舞狮", "fest_lantern": "元宵吃汤圆", "fest_dragonboat": "端午吃粽子",
        "look": "东张西望", "tap": "敲桌面", "cube": "玩魔方", "bubbles": "吹泡泡", "bookspirit": "书灵现世", "flower": "凭空生花", "dove": "变鸽子",
        "snack": "偷吃零食", "token": "吃 Token", "mutter": "对屏碎碎念", "gamer": "玩游戏气急败坏", "animals": "动物环绕", "butterflies": "蝴蝶蜜蜂",
        "juggle": "三球抛接", "cards": "扑克魔术", "flute": "吹笛子", "violin": "小提琴", "dance_skirt": "裙摆舞", "dance_otaku": "宅舞",
        "dance_swing": "摇摆舞", "dressup": "换装试色", "toycar": "玩具汽车", "watergun": "玩水枪", "gomoku": "下五子棋", "top": "抽陀螺",
        "cat": "撸猫", "shuttlecock": "踢毽子", "rockinghorse": "骑木马", "pagebeat": "拍书打节奏", "rice": "吃白饭", "hotpot": "涮火锅",
        "crab": "吃大闸蟹", "watermelon": "吃西瓜", "qingtuan": "清明吃青团", "laba": "腊八喝粥", "chongyanggao": "重阳吃糕", "kite": "放风筝",
        "fan": "摇扇纳凉", "leaves": "被落叶淹没", "qixi": "七夕穿针", "zhongyuan": "中元放河灯", "chongyang": "重阳赏菊",
        "walk_crab": "螃蟹步", "walk_float": "飘着走", "run_left": "往左跑",
        "quota_full": "钱袋满溢", "quota_jingle": "金袋叮当", "quota_count": "数金皱眉", "quota_empty": "袋空如洗", "quota_broke": "分文不剩",
        "fest_midautumn": "中秋赏月", "fest_halloween": "万圣节讨糖", "fest_christmas": "圣诞装点彩树",
        "toes": "伸脚趾", "nails": "咬指甲", "scratch": "抓痒", "leg_bounce": "抖腿", "finger_count": "掰手指", "eye_rub": "揉眼睛",
        "tummy": "摸肚子", "hand_flick": "甩手甩水", "wrist_roll": "转手腕", "pen_spin": "转笔", "leaf_flute": "吹叶笛", "glass_harp": "弹玻璃杯沿",
        "air_guitar": "空气吉他", "music_box": "手摇八音盒", "woodfish": "敲木鱼", "curtsy": "淑女屈膝礼", "jenga": "叠叠乐", "dandelion": "吹蒲公英",
        "forehead_flick": "弹脑门", "bubble_wrap": "戳泡泡纸", "skip_stone": "打水漂", "diabolo": "抖空竹", "hat_toss": "抛帽接帽",
        "apple_toss": "抛接小苹果", "dice": "摇骰盅", "cats_cradle": "翻花绳", "shadow_step": "踩影子", "umbrella_spin": "转伞", "plate_spin": "转盘子",
        "chocolate": "分巧克力", "shaved_ice": "刨冰屑", "chestnut": "剥栗子", "pudding": "吸布丁", "cracker": "咬脆饼", "corn": "啃玉米",
        "soup": "喝汤吹凉", "fishbone": "挑鱼刺", "onigiri": "捏饭团", "soda": "摇汽水瓶", "sweet_potato": "烤红薯", "honey": "舀蜂蜜",
        "sunshade": "举手遮阳偷看", "snow_step": "原地踏雪", "cicada": "听蝉", "hand_warmer": "抱暖手炉", "snowflake": "掌心接雪花",
        "raindrop": "接雨滴", "warm_breath": "搓手哈气取暖", "clear_umbrella": "撑透明小伞", "windy": "被风吹乱发型", "beads": "串珠链",
        "paper_boat": "折小纸船", "clay": "捏陶土", "ink": "磨墨", "grasshopper": "编草蚱蜢", "abacus": "拨算盘珠", "mutter_lazy": "犯懒碎碎念",
    ]

    func fillMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if userHidden { menu.add("叫她出来") { [weak self] in self?.setUserHidden(false) }; menu.sep() }
        menu.add("摸摸头") { [weak self] in self?.js("handleClick('pat')") }
        menu.add("戳一下") { [weak self] in self?.js("handleClick('poke')") }
        let have = actionPoses
        if !have.isEmpty {
            menu.sub("动作") { root in
                var used = Set<String>()
                for (group, poses) in Pet.actionGroups {
                    let list = poses.filter { have.contains($0) }
                    if list.isEmpty { continue }
                    root.sub(group) { m in
                        for p in list { used.insert(p); m.add(Pet.actionNames[p] ?? p) { [weak self] in self?.playAction(p) } }
                    }
                }
                let others = have.subtracting(used).sorted()
                if !others.isEmpty { root.sub("其他") { m in for p in others { m.add(p) { [weak self] in self?.playAction(p) } } } }
            }
        }
        menu.sep()
        menu.sub("外观") { m in
            m.sub("人物大小") { s in
                for v in [0.6, 0.8, 1.0, 1.2, 1.4, 1.6] {
                    s.add("\(Int(v * 100))%", checked: abs(Pet.scale - v) < 0.01) { [weak self] in self?.set("size", v) }
                }
            }
            m.add("显示名字", checked: Pet.showName) { [weak self] in self?.set("showName", !Pet.showName) }
            m.add("改名字…") { [weak self] in self?.askRename() }
            m.sub("背景光晕") { s in
                for (id, label) in [("auto", "自动（深色模式下不显示）"), ("on", "始终显示"), ("off", "关闭")] {
                    s.add(label, checked: Pet.auraMode == id) { [weak self] in self?.set("auraMode", id) }
                }
            }
            m.sub("额度显示") { s in
                s.add("文字", checked: Pet.quotaStyle == "text") { [weak self] in self?.set("quotaStyle", "text") }
                s.add("额度条", checked: Pet.quotaStyle == "bars") { [weak self] in self?.set("quotaStyle", "bars") }
            }
            m.add("省电模式", checked: Store.flag("powerSave", false)) { [weak self] in self?.set("powerSave", !Store.flag("powerSave", false)) }
        }
        menu.sub("互动") { m in
            m.add("随机小动作", checked: Store.flag("idleEnabled")) { [weak self] in self?.set("idleEnabled", !Store.flag("idleEnabled")) }
            m.sub("活跃程度") { s in
                let cur = Store.string("idleFrequency", "normal", allowed: ["quiet", "normal", "lively"])
                for (id, label) in [("quiet", "安静"), ("normal", "标准"), ("lively", "活泼")] {
                    s.add(label, checked: cur == id) { [weak self] in self?.set("idleFrequency", id) }
                }
            }
            m.sep()
            m.add("点击 Q 弹", checked: Store.flag("clickBounce")) { [weak self] in self?.set("clickBounce", !Store.flag("clickBounce")) }
            m.add("碰边动作（撞头、摔倒）", checked: Store.flag("tumbleActions")) { [weak self] in self?.set("tumbleActions", !Store.flag("tumbleActions")) }
            m.add("拖拽与抛掷", checked: Store.flag("physicsEnabled")) { [weak self] in self?.set("physicsEnabled", !Store.flag("physicsEnabled")) }
            m.add("顶部反弹", checked: Store.flag("ceilingBounce")) { [weak self] in self?.set("ceilingBounce", !Store.flag("ceilingBounce")) }
            m.sub("重力") { s in
                let g = Store.number("gravity", 1400, 0, 3000)
                for (v, label) in [(0.0, "无重力"), (700.0, "轻"), (1400.0, "标准"), (2400.0, "重")] {
                    s.add(label, checked: abs(g - v) < 1) { [weak self] in self?.set("gravity", v) }
                }
            }
        }
        menu.sub("通知") { m in
            m.add("完成或出错时通知", checked: Store.flag("notifyResults")) { [weak self] in self?.set("notifyResults", !Store.flag("notifyResults")) }
            m.add("等待授权或回答时通知", checked: Store.flag("notifyWaiting")) { [weak self] in self?.set("notifyWaiting", !Store.flag("notifyWaiting")) }
            m.add("仅在终端 / Claude 不在前台时", checked: Store.flag("notifyBackgroundOnly")) { [weak self] in
                self?.set("notifyBackgroundOnly", !Store.flag("notifyBackgroundOnly"))
            }
        }
        menu.sub("接入 Claude") { m in
            let on = Integration.pluginInstalled
            m.add("Claude Code 插件", checked: on) { Integration.toggle(install: !on) }
            let seen = Integration.seenText
            let info = NSMenuItem(title: seen, action: nil, keyEquivalent: ""); info.isEnabled = false; m.addItem(info)
            m.sep()
            m.add("登录时自动启动", checked: LoginItem.enabled) { LoginItem.toggle() }
            m.add("打开数据文件夹") { NSWorkspace.shared.open(Store.data) }
        }
        menu.sep()
        menu.add("回到默认位置") { [weak self] in self?.recenter() }
        let hk = Store.flag("hideHotkey")
        if !userHidden { menu.add(hk && !hotkeyFailed ? "暂时隐藏（⌃⌥P）" : "暂时隐藏") { [weak self] in self?.setUserHidden(true) } }
        menu.add(hotkeyFailed ? "隐藏快捷键 ⌃⌥P（被占用）" : "隐藏快捷键 ⌃⌥P", checked: hk) { [weak self] in self?.set("hideHotkey", !hk) }
        menu.sep()
        menu.add("关于 \(Store.appName)…") { Pet.about() }
        menu.add("退出 \(Store.appName)") { [weak self] in self?.userQuit() }
    }

    private func askRename() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "给她改个名字"
        a.informativeText = "最多 20 个字符；留空恢复默认名字 claudia。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = Store.defaults.string(forKey: "name") ?? ""
        field.placeholderString = "claudia"
        a.accessoryView = field
        a.addButton(withTitle: "保存"); a.addButton(withTitle: "取消")
        a.window.initialFirstResponder = field
        if a.runModal() == .alertFirstButtonReturn { rename(field.stringValue) }
    }

    static func about() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "\(Store.appName) \(Store.version)（macOS）"
        a.informativeText = """
        Claude 大小姐 claudia 的 macOS 桌宠。非官方同人项目，与 Anthropic 无关。

        参照 claudia-pet（kirito1207，Windows 版）实现，网页动画层沿用其代码（MIT，基于 CrossPet / dsh-pet）。
        角色立绘、动画与台词来自 claudia-pet / CrossPet / hunmer 的 claude-pet 动作包，按 CC BY-NC-SA 4.0 授权：须署名、不得商用、相同方式共享。
        Claude、Clawd 的相关权利归 Anthropic。
        """
        a.addButton(withTitle: "好")
        a.addButton(withTitle: "上游项目")
        if a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(URL(string: "https://github.com/kirito1207/claudia-pet")!) }
    }
}

// ---------------- 接入 Claude Code 插件 ----------------
/// 把程序里的 plugin 文件夹加进 ~/.claude/settings.json 的 env.CLAUDE_CODE_PLUGIN_DIRS（多个目录用 : 隔开，别人的照留）。
/// 改之前先备份成 settings.json.bak-claudia-<时间>，只留最近 3 份。新开的 Claude Code 会话生效。
enum Integration {
    static var settingsFile: URL {
        let dir = Store.env("CLAUDE_CONFIG_DIR").map { URL(fileURLWithPath: $0) } ?? Store.home.appendingPathComponent(".claude")
        return dir.appendingPathComponent("settings.json")
    }
    static var pluginDir: String { Store.plugin.standardizedFileURL.path }
    static func dirs(_ s: [String: Any]?) -> [String] {
        ((s?["env"] as? [String: Any])?["CLAUDE_CODE_PLUGIN_DIRS"] as? String)?
            .split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
    }
    static func same(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: (a as NSString).expandingTildeInPath).standardizedFileURL.path == URL(fileURLWithPath: b).standardizedFileURL.path
    }
    static var pluginInstalled: Bool { dirs(Store.readJSON(settingsFile)).contains { same($0, pluginDir) } }

    static var seenText: String {
        guard let s = try? String(contentsOf: Store.state.appendingPathComponent("seen-plugin"), encoding: .utf8),
              let ts = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "还没收到过 Claude Code 的消息" }
        let ago = Date().timeIntervalSince1970 - ts
        let t = ago < 60 ? "刚刚" : ago < 3600 ? "\(Int(ago / 60)) 分钟前" : ago < 86400 ? "\(Int(ago / 3600)) 小时前" : "\(Int(ago / 86400)) 天前"
        return "上次收到消息：\(t)"
    }

    static func toggle(install: Bool) {
        var message: String
        do { message = try set(install: install) } catch { message = "没有完成：\(error.localizedDescription)" }
        Store.log("接入插件 \(install)：\(message)")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "接入 Claude Code"; a.informativeText = message; a.runModal()
    }

    static func set(install: Bool) throws -> String {
        let fm = FileManager.default, file = settingsFile
        if install && !fm.fileExists(atPath: Store.plugin.appendingPathComponent(".claude-plugin/plugin.json").path) {
            throw NSError(domain: Store.appName, code: 1, userInfo: [NSLocalizedDescriptionKey: "没找到插件文件夹：\(pluginDir)"])
        }
        var settings = Store.readJSON(file)
        if settings == nil && fm.fileExists(atPath: file.path) {
            throw NSError(domain: Store.appName, code: 2, userInfo: [NSLocalizedDescriptionKey: "读不懂 \(file.path)，这次没有改。"])
        }
        settings = settings ?? [:]
        var list = dirs(settings).filter { !same($0, pluginDir) }
        if install { list.append(pluginDir) }
        var env = (settings!["env"] as? [String: Any]) ?? [:]
        if list.isEmpty { env.removeValue(forKey: "CLAUDE_CODE_PLUGIN_DIRS") } else { env["CLAUDE_CODE_PLUGIN_DIRS"] = list.joined(separator: ":") }
        if env.isEmpty { settings!.removeValue(forKey: "env") } else { settings!["env"] = env }
        var backup: String?
        if fm.fileExists(atPath: file.path) {
            let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
            let copy = file.path + ".bak-claudia-" + f.string(from: Date())
            try? fm.removeItem(atPath: copy)
            try fm.copyItem(atPath: file.path, toPath: copy)
            backup = copy
            let dir = file.deletingLastPathComponent()
            let olds = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasPrefix(file.lastPathComponent + ".bak-claudia-") }.sorted(by: >).dropFirst(3)
            for o in olds { try? fm.removeItem(at: dir.appendingPathComponent(o)) }
        }
        try Store.writeJSON(file, settings!)
        return (install ? "已接入 Claude Code 插件。新开的 Claude Code 会话生效。" : "已撤销 Claude Code 插件。")
            + "\n\n改了：\(file.path)" + (backup.map { "\n备份：\($0)" } ?? "")
            + (install ? "\n\n注意：插件路径在 \(Store.appName).app 里面，以后挪动了程序要重新接入一次。" : "")
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func toggle() {
        do {
            if enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert(); a.messageText = "设置登录启动失败"
            a.informativeText = "\(error.localizedDescription)\n\n可以在「系统设置 → 通用 → 登录项」里手动添加 \(Store.appName)。"
            a.runModal()
        }
    }
}
