import AppKit

// claudia-pet × Codex CLI
// Codex 的 hooks 每个事件起一个进程，把 JSON 从 stdin 交过来。这里就是那个进程：
//   ~/.claudia/bin/claudia-hook --hook codex   （软链到 claudia-pet.app 里的可执行文件）
// 读完事件，写和 Claude Code 插件同样格式的状态文件（文件名前缀 codex-），几十毫秒内退出，不启动界面。
//   codex-state.json      现在在干什么
//   codex-sessions.json   多个会话各自在干什么（会话 id 前面加 codex:，和 Claude 的不会撞）
//   codex-quota.json      5 小时 / 每周额度（从会话记录 transcript_path 里最后一条 rate_limits 读）
//   codex-notify-*.json   完成 / 出错 / 等你确认的通知
// 只写本机文件，不往 stdout 输出（SessionStart 的输出会被当成上下文），出什么错都以 0 退出，不影响 Codex。
enum CodexHook {
    static let bigJobTools = 8   // 一轮里用了这么多次工具，完成时「得意」一下

    static func run() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        if let e = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] {
            handle(e)
        }
        exit(0)
    }

    static func handle(_ e: [String: Any]) {
        let event = e["hook_event_name"] as? String ?? ""
        let rawSid = e["session_id"] as? String ?? "default"
        let sid = "codex:" + rawSid
        let now = Date().timeIntervalSince1970
        let tool = e["tool_name"] as? String ?? ""
        write("seen-codex", String(Int(now)))   // 心跳：菜单里显示「上次收到消息」

        switch event {
        case "SessionStart":
            // 子代理开始时也会来一次 SessionStart（带的是主会话的 id）：这一轮还在干活，就当她在派活，不回待机
            let busy = turn(sid) { _ in }["active", default: 0] > 0
            if busy || e["agent_id"] != nil {
                setState(sid, "delegating", "PreToolUse", "", now)
            } else {
                ensurePet()
                setState(sid, "idle", "SessionStart", "", now)
                readQuota(e["transcript_path"] as? String)
            }
        case "UserPromptSubmit":
            ensurePet()
            turn(sid) { $0 = ["active": 1] }
            setState(sid, "listening", "UserPromptSubmit", "", now)
        case "PreToolUse":
            turn(sid) { $0["tools", default: 0] += 1 }
            setState(sid, pose(tool: tool, input: e["tool_input"]), "PreToolUse", tool, now)
        case "PostToolUse":
            setState(sid, failed(e["tool_response"]) ? "oops" : "thinking", "PostToolUse", tool, now)
        case "PermissionRequest":
            setState(sid, "asking", "Notification", tool, now)
            notify(rawSid, "waiting")
        case "PostModelRequest":
            // 一次请求失败可能会重试：先记下，等这一轮停下时再算出没出错
            let bad = (e["status"] as? String) == "failed"
            turn(sid) { $0["failed"] = bad ? 1 : 0 }
        case "Stop":
            let t = turn(sid) { $0 = [:] }
            if t["failed", default: 0] > 0 {
                setState(sid, "oops", "Stop", "", now)
                notify(rawSid, "error")
            } else {
                setState(sid, t["tools", default: 0] >= bigJobTools ? "proud" : "happy", "Stop", "", now)
                notify(rawSid, "complete")
            }
            readQuota(e["transcript_path"] as? String)
        case "Interrupt":
            turn(sid) { $0 = [:] }
            setState(sid, "surprised", "Stop", "", now)
        case "PreCompact":
            setState(sid, "compact", "PreCompact", "", now)
        case "PostCompact":
            // 手动 /compact 压完这一轮就结束了，自己收尾；自动压缩之后还接着干活
            if (e["trigger"] as? String) == "manual" { setState(sid, "happy", "Stop", "", now) }
            else { setState(sid, "thinking", "PostCompact", "", now) }
        case "SessionEnd":
            removeSession(sid)
        default:
            break
        }
    }

    // ---------------- 工具 → 姿势 ----------------
    static func pose(tool: String, input: Any?) -> String {
        let t = tool.lowercased()
        if ["bash", "shell", "exec_command", "local_shell", "unified_exec"].contains(t) { return shellPose(command(input)) }
        if t.range(of: "patch|write|edit|replace|create|plan", options: .regularExpression) != nil { return "writing" }
        if t.range(of: "read|grep|glob|list|view|cat", options: .regularExpression) != nil { return "reading" }
        if t.range(of: "web|fetch|browse|search|http", options: .regularExpression) != nil { return "searching" }
        if t.range(of: "agent|task|subagent|delegate|spawn", options: .regularExpression) != nil { return "delegating" }
        return "running"
    }

    /// tool_input 里的命令：可能是字符串，也可能是 ["bash", "-lc", "…"] 这样的数组
    static func command(_ input: Any?) -> String {
        guard let d = input as? [String: Any] else { return "" }
        let c = d["command"] ?? d["cmd"]
        if let s = c as? String { return s }
        if let a = c as? [String] {
            if let i = a.firstIndex(where: { $0 == "-lc" || $0 == "-c" }), i + 1 < a.count { return a[i + 1] }
            return a.joined(separator: " ")
        }
        return ""
    }

    /// Codex 读文件、搜代码也是跑命令：看第一个真正干活的命令是什么
    static func shellPose(_ cmd: String) -> String {
        let segments = cmd.components(separatedBy: CharacterSet(charactersIn: "&;|\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("cd ") }
        guard let first = segments.first else { return "running" }
        let words = first.split(separator: " ").map(String.init).filter { !$0.contains("=") || $0.hasPrefix("-") }
        guard let head = words.first.map({ ($0 as NSString).lastPathComponent }) else { return "running" }
        let readers: Set<String> = ["cat", "sed", "head", "tail", "less", "more", "rg", "grep", "ls", "find", "fd", "nl", "wc",
                                    "tree", "file", "stat", "jq", "bat", "awk", "diff"]
        if readers.contains(head) { return "reading" }
        if head == "git", words.count > 1, ["log", "show", "diff", "status", "blame", "grep"].contains(words[1]) { return "reading" }
        if ["curl", "wget", "http", "xh"].contains(head) { return "searching" }
        return "running"
    }

    static func failed(_ response: Any?) -> Bool {
        guard let r = response as? [String: Any] else { return false }
        if let code = (r["exit_code"] ?? r["exitCode"]) as? Int { return code != 0 }
        if let ok = r["success"] as? Bool { return !ok }
        if let err = r["is_error"] as? Bool { return err }
        return false
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

    /// 几个 Codex 会话的 hook 进程可能同时改同一个文件：读、改、写整个过程加锁
    static func locked<T>(_ body: () -> T) -> T {
        try? FileManager.default.createDirectory(at: Store.state, withIntermediateDirectories: true)
        let fd = open(Store.state.appendingPathComponent(".codex.lock").path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        return body()
    }

    static func setState(_ sid: String, _ pose: String, _ event: String, _ tool: String, _ ts: Double) {
        write("codex-state.json", ["pose": pose, "event": event, "tool": tool, "ts": ts, "sid": sid, "agent": "codex", "noticeV": 1])
        locked {
            let file = Store.state.appendingPathComponent("codex-sessions.json")
            var known = Store.readJSON(file) ?? [:]
            known[sid] = ["pose": pose, "event": event, "ts": ts]
            known = known.filter { ts - (($0.value as? [String: Any])?["ts"] as? Double ?? 0) <= 600 }
            try? Store.writeJSON(file, known)
        }
    }

    static func removeSession(_ sid: String) {
        locked {
            let file = Store.state.appendingPathComponent("codex-sessions.json")
            guard var known = Store.readJSON(file), known[sid] != nil else { return }
            known.removeValue(forKey: sid)
            try? Store.writeJSON(file, known)
        }
        _ = turn(sid) { $0 = [:] }
    }

    /// 每个会话这一轮的计数（用了几次工具、最近一次请求是否失败）。返回改之前的值
    @discardableResult
    static func turn(_ sid: String, _ change: (inout [String: Int]) -> Void) -> [String: Int] {
        locked {
            let file = Store.state.appendingPathComponent("codex-turns.json")
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
        let name = "codex-notify-\(safe.prefix(100)).json"
        let ts = Date().timeIntervalSince1970
        locked {
            let file = Store.state.appendingPathComponent(name)
            var events = (Store.readJSON(file)?["events"] as? [[String: Any]]) ?? []
            events = Array(events.filter { ts - ($0["ts"] as? Double ?? 0) < 120 }.suffix(31))
            events.append(["id": "codex:\(rawSid):\(Int(ts * 1000))", "kind": kind, "ts": ts])
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
        p.standardOutput = FileHandle.nullDevice   // 不占着 Codex 的管道，免得它等 open 退出
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // ---------------- 额度 ----------------
    /// 会话记录（rollout-*.jsonl）里 token_count 事件带着 rate_limits：
    ///   {"timestamp": "…", "type": "event_msg", "payload": {"type": "token_count", "rate_limits": {"primary": {...}, "secondary": {...}}}}
    /// 每个窗口 {used_percent, window_minutes, resets_at（秒）或 resets_in_seconds}。从文件末尾往前找最后一条。
    static func readQuota(_ path: String?) {
        guard let path, let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let chunk: UInt64 = 512 * 1024
        try? h.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return }
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let payload = obj["payload"] as? [String: Any] ?? obj
            guard let limits = (payload["rate_limits"] ?? (payload["msg"] as? [String: Any])?["rate_limits"]) as? [String: Any] else { continue }
            let at = (obj["timestamp"] as? String).flatMap(parseDate) ?? Date()
            if let q = quota(limits, at: at) { write("codex-quota.json", q) }
            return
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// 和 Claude Code 插件的 quotaOf 同样的格式：{text, low, bars: [{label, left, reset}]}
    static func quota(_ limits: [String: Any], at: Date) -> [String: Any]? {
        var shown: [(label: String, used: Double, reset: Double?)] = []
        for (key, fallback) in [("primary", "5小时"), ("secondary", "本周")] {
            guard let w = limits[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
            var label = fallback
            if let m = (w["window_minutes"] as? NSNumber)?.intValue, m > 0 {
                label = m >= 10_000 && m <= 10_200 ? "本周" : m % 1440 == 0 ? "\(m / 1440)天" : m % 60 == 0 ? "\(m / 60)小时" : "\(m)分钟"
            }
            var reset: Double?
            if let r = (w["resets_at"] as? NSNumber)?.doubleValue { reset = r > 1e12 ? r / 1000 : r }
            else if let s = (w["resets_in_seconds"] as? NSNumber)?.doubleValue { reset = at.timeIntervalSince1970 + s }
            shown.append((label, used, reset))
        }
        guard !shown.isEmpty else { return nil }
        let top = shown.indices.max { shown[$0].used < shown[$1].used }!
        let pad = { (n: Int) in String(format: "%02d", n) }
        let parts = shown.indices.map { i -> String in
            let l = shown[i]
            var piece = "\(l.label) 已用 \(Int(min(100, max(0, l.used.rounded()))))%"
            if i == top, let r = l.reset {
                let d = Date(timeIntervalSince1970: r), c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: d)
                piece += r - Date().timeIntervalSince1970 < 86_400 ? " · \(pad(c.hour!)):\(pad(c.minute!)) 重置" : " · \(c.month!)/\(c.day!) 重置"
            }
            return piece
        }
        let bars: [[String: Any]] = shown.map { l in
            var b: [String: Any] = ["label": l.label, "left": max(0, 100 - l.used.rounded()) / 100]
            if let r = l.reset { b["reset"] = Int(r.rounded()) }
            return b
        }
        return ["text": parts.joined(separator: " ｜ "), "low": shown[top].used >= 90, "bars": bars]
    }
}

// ---------------- 接入 Codex ----------------
/// 往 ~/.codex/hooks.json（有 CODEX_HOME 就用它）里合并几条 hook，命令都是 ~/.claudia/bin/claudia-hook --hook codex。
/// 只增删命令是这个的条目，你自己的 hook 照留；改之前先备份。Codex 要你在 /hooks 里信任一次才会运行。
enum CodexIntegration {
    static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                         "PostModelRequest", "Stop", "Interrupt", "PreCompact", "PostCompact"]
    static var codexHome: URL { Store.env("CODEX_HOME").map { URL(fileURLWithPath: $0) } ?? Store.home.appendingPathComponent(".codex") }
    static var hooksFile: URL { codexHome.appendingPathComponent("hooks.json") }
    /// 固定路径的软链：程序挪了位置、升级了，hooks.json 里的命令不变，不用在 Codex 里重新信任
    static var hookLink: URL { Store.data.appendingPathComponent("bin/claudia-hook") }
    static var command: String { "\"\(hookLink.path)\" --hook codex" }

    static func ours(_ handler: Any) -> Bool {
        guard let c = (handler as? [String: Any])?["command"] as? String else { return false }
        return c.contains("/claudia-hook") && c.contains("--hook codex")
    }

    static var installed: Bool {
        guard let hooks = Store.readJSON(hooksFile)?["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            ((groups as? [[String: Any]]) ?? []).contains { (($0["hooks"] as? [Any]) ?? []).contains(where: ours) }
        }
    }

    static var seenText: String {
        guard let s = try? String(contentsOf: Store.state.appendingPathComponent("seen-codex"), encoding: .utf8),
              let ts = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return installed ? "还没收到过 Codex 的消息（在 Codex 里用 /hooks 信任了吗？）" : "还没收到过 Codex 的消息"
        }
        return "上次收到消息：" + Integration.ago(ts)
    }

    /// 软链指向现在这个程序（每次启动时顺手修一下，程序挪过位置也能接上）
    static func refreshLink() {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return }
        let fm = FileManager.default, link = hookLink.path
        if (try? fm.destinationOfSymbolicLink(atPath: link)) == exe { return }
        try? fm.createDirectory(at: hookLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(atPath: link)
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: exe)
    }

    static func toggle(install: Bool) {
        var message: String
        do { message = try set(install: install) } catch { message = "没有完成：\(error.localizedDescription)" }
        Store.log("接入 Codex \(install)：\(message)")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "接入 Codex"; a.informativeText = message; a.runModal()
    }

    static func set(install: Bool) throws -> String {
        let fm = FileManager.default, file = hooksFile
        var root = Store.readJSON(file)
        if root == nil && fm.fileExists(atPath: file.path) {
            throw NSError(domain: Store.appName, code: 2, userInfo: [NSLocalizedDescriptionKey: "读不懂 \(file.path)，这次没有改。"])
        }
        root = root ?? [:]
        var hooks = root!["hooks"] as? [String: Any] ?? [:]
        // 先把我们的条目都去掉（只留你自己的），装的话再加回去
        for (event, value) in hooks {
            var groups = (value as? [[String: Any]]) ?? []
            groups = groups.compactMap { g in
                guard let hs = g["hooks"] as? [Any], hs.contains(where: ours) else { return g }
                let rest = hs.filter { !ours($0) }
                if rest.isEmpty { return nil }
                var g = g; g["hooks"] = rest; return g
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        if install {
            refreshLink()
            for event in events {
                var groups = (hooks[event] as? [[String: Any]]) ?? []
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
                hooks[event] = groups
            }
        }
        if hooks.isEmpty { root!.removeValue(forKey: "hooks") } else { root!["hooks"] = hooks }
        let backup = try Integration.backup(file)
        if root!.isEmpty && !fm.fileExists(atPath: file.path) { return "本来就没有接入。" }
        try Store.writeJSON(file, root!)
        var msg = (install ? "已接入 Codex。\n\n还差一步：在 Codex 里输入 /hooks，信任 claudia-pet 加的这几条 hook（只用信任一次），新开的会话生效。"
                           : "已撤销 Codex 接入。")
            + "\n\n改了：\(file.path)" + (backup.map { "\n备份：\($0)" } ?? "")
        if install, let toml = try? String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8),
           toml.range(of: #"(?m)^\s*(codex_)?hooks\s*=\s*false"#, options: .regularExpression) != nil {
            msg += "\n\n注意：你的 config.toml 里把 hooks 关掉了（[features] hooks = false），要打开才会生效。"
        }
        return msg
    }
}
