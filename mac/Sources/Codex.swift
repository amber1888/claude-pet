import AppKit

// claudia-pet × Codex CLI：~/.claudia/bin/claudia-hook --hook codex
// 写哪些文件、怎么写见 Hooks.swift（前缀 codex-）。额度从会话记录 transcript_path 里最后一条 rate_limits 读。
enum CodexHook {
    static let bigJobTools = 8   // 一轮里用了这么多次工具，完成时「得意」一下

    static func run() -> Never { HookOut.run(agent: "codex", handle) }

    static func handle(_ e: [String: Any]) {
        let event = e["hook_event_name"] as? String ?? ""
        let rawSid = e["session_id"] as? String ?? "default"
        let sid = "codex:" + rawSid
        let now = Date().timeIntervalSince1970
        let tool = e["tool_name"] as? String ?? ""
        HookOut.write("seen-codex", String(Int(now)))   // 心跳：菜单里显示「上次收到消息」

        switch event {
        case "SessionStart":
            // 子代理开始时也会来一次 SessionStart（带的是主会话的 id）：这一轮还在干活，就当她在派活，不回待机
            let busy = HookOut.turn(sid) { _ in }["active", default: 0] > 0
            if busy || e["agent_id"] != nil {
                HookOut.setState(sid, "delegating", "PreToolUse", "", now)
            } else {
                HookOut.ensurePet()
                HookOut.setState(sid, "idle", "SessionStart", "", now)
                readQuota(e["transcript_path"] as? String)
            }
        case "UserPromptSubmit":
            HookOut.ensurePet()
            HookOut.turn(sid) { $0 = ["active": 1] }
            HookOut.setState(sid, "listening", "UserPromptSubmit", "", now)
        case "PreToolUse":
            HookOut.turn(sid) { $0["tools", default: 0] += 1 }
            HookOut.setState(sid, pose(tool: tool, input: e["tool_input"]), "PreToolUse", tool, now)
        case "PostToolUse":
            HookOut.setState(sid, failed(e["tool_response"]) ? "oops" : "thinking", "PostToolUse", tool, now)
        case "PermissionRequest":
            HookOut.setState(sid, "asking", "Notification", tool, now)
            HookOut.notify(rawSid, "waiting")
        case "PostModelRequest":
            // 一次请求失败可能会重试：先记下，等这一轮停下时再算出没出错
            let bad = (e["status"] as? String) == "failed"
            HookOut.turn(sid) { $0["failed"] = bad ? 1 : 0 }
        case "Stop":
            let t = HookOut.turn(sid) { $0 = [:] }
            if t["failed", default: 0] > 0 {
                HookOut.setState(sid, "oops", "Stop", "", now)
                HookOut.notify(rawSid, "error")
            } else {
                HookOut.setState(sid, t["tools", default: 0] >= bigJobTools ? "proud" : "happy", "Stop", "", now)
                HookOut.notify(rawSid, "complete")
            }
            readQuota(e["transcript_path"] as? String)
        case "Interrupt":
            HookOut.turn(sid) { $0 = [:] }
            HookOut.setState(sid, "surprised", "Stop", "", now)
        case "PreCompact":
            HookOut.setState(sid, "compact", "PreCompact", "", now)
        case "PostCompact":
            // 手动 /compact 压完这一轮就结束了，自己收尾；自动压缩之后还接着干活
            if (e["trigger"] as? String) == "manual" { HookOut.setState(sid, "happy", "Stop", "", now) }
            else { HookOut.setState(sid, "thinking", "PostCompact", "", now) }
        case "SessionEnd":
            HookOut.removeSession(sid)
        default:
            break
        }
    }

    // ---------------- 工具 → 姿势 ----------------
    static func pose(tool: String, input: Any?) -> String {
        let t = tool.lowercased()
        if ["bash", "shell", "exec_command", "local_shell", "unified_exec", "run_terminal_command"].contains(t) { return shellPose(command(input)) }
        if t.hasPrefix("get_") && t.hasSuffix("_output") { return "running" }   // Grok：等后台命令 / 子代理的输出
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
        if let s = response as? String {   // Grok：结果太大时整个变成一段截断了的文本，只认里面的 "exit_code": N
            guard let m = s.range(of: #""exit_code":\s*(-?\d+)"#, options: .regularExpression) else { return false }
            return Int(s[m].split(separator: ":").last!.trimmingCharacters(in: .whitespaces)) != 0
        }
        guard let r = response as? [String: Any] else { return false }
        if let code = (r["exit_code"] ?? r["exitCode"]) as? Int { return code != 0 }
        if let ok = r["success"] as? Bool { return !ok }
        if let err = r["is_error"] as? Bool { return err }
        return false
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
            if let q = quota(limits, at: at) { HookOut.write("codex-quota.json", q) }
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
    static var command: String { HookOut.command("codex") }

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

    static var seenText: String { HookOut.seenText("codex", name: "Codex", installed: installed, hint: "（在 Codex 里用 /hooks 信任了吗？）") }

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
            HookOut.refreshLink()
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
