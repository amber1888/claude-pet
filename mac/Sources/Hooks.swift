import AppKit

// 命令行 hook 共用的部分（Codex.swift、Grok.swift）。
// Codex / Grok 每个事件起一个进程，把 JSON 从 stdin 交过来：~/.claudia/bin/claudia-hook --hook <家>（软链到程序本身）。
// 读完事件写状态文件（前缀是家的名字，格式和 Claude Code 插件写的一样），几十毫秒内退出，不启动界面：
//   <家>-state.json      现在在干什么
//   <家>-sessions.json   多个会话各自在干什么（会话 id 前面加「<家>:」，几家不会撞）
//   <家>-quota.json      额度
//   <家>-turns.json      每个会话这一轮的计数
//   <家>-notify-*.json   完成 / 出错 / 等你确认的通知
// 只写本机文件，不往 stdout 输出（有的事件的输出会被当成上下文），出什么错都以 0 退出，不影响对方。
enum HookOut {
    /// 这个进程替哪家写：codex / grok
    static private(set) var agent = "codex"

    static func run(agent: String, _ handle: ([String: Any]) -> Void) -> Never {
        self.agent = agent
        let input = FileHandle.standardInput.readDataToEndOfFile()
        if let e = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] {
            handle(e)
        }
        exit(0)
    }

    // ---------------- 软链 ----------------
    /// 固定路径的软链：程序挪了位置、升级了，配置里的命令不变（Codex 不用重新信任）
    static var hookLink: URL { Store.data.appendingPathComponent("bin/claudia-hook") }
    static func command(_ agent: String) -> String { "\"\(hookLink.path)\" --hook \(agent)" }

    /// 软链指向现在这个程序（每次启动时顺手修一下，程序挪过位置也能接上）
    static func refreshLink() {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return }
        let fm = FileManager.default, link = hookLink.path
        if (try? fm.destinationOfSymbolicLink(atPath: link)) == exe { return }
        try? fm.createDirectory(at: hookLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(atPath: link)
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: exe)
    }

    /// 菜单里那行「上次收到消息」
    static func seenText(_ agent: String, name: String, installed: Bool, hint: String = "") -> String {
        guard let s = try? String(contentsOf: Store.state.appendingPathComponent("seen-\(agent)"), encoding: .utf8),
              let ts = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "还没收到过 \(name) 的消息" + (installed ? hint : "")
        }
        return "上次收到消息：" + Integration.ago(ts)
    }

    // ---------------- 写文件 ----------------
    static func write(_ name: String, _ value: Any) {
        let url = Store.state.appendingPathComponent(name)
        if let s = value as? String {
            try? FileManager.default.createDirectory(at: Store.state, withIntermediateDirectories: true)
            try? s.write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? Store.writeJSON(url, value)
        }
    }

    /// 几个会话的 hook 进程可能同时改同一个文件：读、改、写整个过程加锁
    static func locked<T>(_ body: () -> T) -> T {
        try? FileManager.default.createDirectory(at: Store.state, withIntermediateDirectories: true)
        let fd = open(Store.state.appendingPathComponent(".\(agent).lock").path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        return body()
    }

    static func setState(_ sid: String, _ pose: String, _ event: String, _ tool: String, _ ts: Double) {
        write("\(agent)-state.json", ["pose": pose, "event": event, "tool": tool, "ts": ts, "sid": sid, "agent": agent, "noticeV": 1])
        locked {
            let file = Store.state.appendingPathComponent("\(agent)-sessions.json")
            var known = Store.readJSON(file) ?? [:]
            known[sid] = ["pose": pose, "event": event, "ts": ts]
            known = known.filter { ts - (($0.value as? [String: Any])?["ts"] as? Double ?? 0) <= 600 }
            try? Store.writeJSON(file, known)
        }
    }

    static func removeSession(_ sid: String) {
        locked {
            let file = Store.state.appendingPathComponent("\(agent)-sessions.json")
            guard var known = Store.readJSON(file), known[sid] != nil else { return }
            known.removeValue(forKey: sid)
            try? Store.writeJSON(file, known)
        }
        turn(sid) { $0 = [:] }
    }

    /// 每个会话这一轮的计数（用了几次工具、最近一次请求是否失败……）。返回改之前的值
    @discardableResult
    static func turn(_ sid: String, _ change: (inout [String: Int]) -> Void) -> [String: Int] {
        locked {
            let file = Store.state.appendingPathComponent("\(agent)-turns.json")
            var all = Store.readJSON(file) ?? [:]
            let now = Date().timeIntervalSince1970
            all = all.filter { now - (($0.value as? [String: Any])?["ts"] as? Double ?? 0) < 86_400 }
            let entry = all[sid] as? [String: Any] ?? [:]
            var counts: [String: Int] = [:]
            for (k, v) in entry where k != "ts" { if let n = v as? Int { counts[k] = n } }
            let before = counts
            change(&counts)
            var out: [String: Any] = counts
            out["ts"] = now
            all[sid] = out
            try? Store.writeJSON(file, all)
            return before
        }
    }

    static func notify(_ rawSid: String, _ kind: String) {
        let safe = rawSid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "default"
        let name = "\(agent)-notify-\(safe.prefix(100)).json"
        let ts = Date().timeIntervalSince1970
        locked {
            let file = Store.state.appendingPathComponent(name)
            var events = (Store.readJSON(file)?["events"] as? [[String: Any]]) ?? []
            events = Array(events.filter { ts - ($0["ts"] as? Double ?? 0) < 120 }.suffix(31))
            events.append(["id": "\(agent):\(rawSid):\(Int(ts * 1000))", "kind": kind, "ts": ts])
            try? Store.writeJSON(file, ["events": events])
        }
    }

    /// 叫她出来：已经在跑就不打扰；你从菜单退出过时，--ensure 会让她自己不出来
    static func ensurePet() {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: Store.bundleID).isEmpty { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-b", Store.bundleID, "--args", "--ensure"]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice   // 不占着对方的管道，免得它等 open 退出
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
