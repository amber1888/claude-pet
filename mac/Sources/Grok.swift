import AppKit

// claudia-pet × Grok Build（xAI 的 grok 命令行）：~/.claudia/bin/claudia-hook --hook grok
// 写哪些文件、怎么写见 Hooks.swift（前缀 grok-）。
// 事件 JSON 里 camelCase 和 Claude 风格的 snake_case 两套键都有（hook_event_name 是 "PreToolUse" 这样的写法），这里读 snake_case。
// 和 Codex 不同的地方（照 grok 1.0.88 实际发来的事件和它自带的 docs/user-guide/10-hooks.md）：
//   - 出错、被打断、限流各有事件：StopFailure（error 是 rate_limit 等）、StopCancelled（reason / cancelledBy）
//   - 退出 grok 时会多来一次 Stop（reason 是 shutdown），只认 reason == end_turn 的
//   - 等授权是 Notification（notification_type == permission_prompt）
//   - 本机看不到剩余额度：额度那行显示这个会话花了多少钱、上下文用了多少（会话目录里的 usage.json / signals.json）
enum GrokHook {
    static func run() -> Never { HookOut.run(agent: "grok", handle) }

    static func handle(_ e: [String: Any]) {
        let event = e["hook_event_name"] as? String ?? ""
        let rawSid = e["session_id"] as? String ?? "default"
        let sid = "grok:" + rawSid
        let now = Date().timeIntervalSince1970
        let tool = e["tool_name"] as? String ?? ""
        let dir = sessionDir(e, rawSid)
        HookOut.write("seen-grok", String(Int(now)))

        switch event {
        case "SessionStart":
            HookOut.ensurePet()
            HookOut.setState(sid, "idle", "SessionStart", "", now)
            // 新会话还没有花费记录：显示 $0.00，顺便换掉上一次留下的「额度用完了」
            HookOut.write("grok-quota.json", dir.flatMap { quota(sessionDir: $0) } ?? ["text": "本次会话 $0.00", "low": false])
        case "UserPromptSubmit":
            HookOut.ensurePet()
            HookOut.turn(sid) { $0 = ["active": 1] }
            HookOut.setState(sid, "listening", "UserPromptSubmit", "", now)
        case "PreToolUse":
            HookOut.turn(sid) { $0["tools", default: 0] += 1 }
            HookOut.setState(sid, CodexHook.pose(tool: tool, input: e["tool_input"]), "PreToolUse", tool, now)
        case "PostToolUse":
            // 命令退出码不是 0 也走这里（不走 PostToolUseFailure）
            HookOut.setState(sid, CodexHook.failed(e["tool_response"]) ? "oops" : "thinking", "PostToolUse", tool, now)
        case "PostToolUseFailure", "PermissionDenied":
            HookOut.setState(sid, "oops", "PostToolUse", tool, now)
        case "Notification":
            if (e["notification_type"] as? String) == "permission_prompt" {
                HookOut.setState(sid, "asking", "Notification", tool, now)
                HookOut.notify(rawSid, "waiting")
            }
        case "SubagentStart":
            HookOut.setState(sid, "delegating", "PreToolUse", "", now)
        case "SubagentStop":
            HookOut.setState(sid, "thinking", "PostToolUse", "", now)
        case "Stop":
            guard (e["reason"] as? String ?? "end_turn") == "end_turn" else { break }
            let t = HookOut.turn(sid) { $0 = [:] }
            HookOut.setState(sid, t["tools", default: 0] >= CodexHook.bigJobTools ? "proud" : "happy", "Stop", "", now)
            HookOut.notify(rawSid, "complete")
            readUsage(dir)
        case "StopFailure":
            HookOut.turn(sid) { $0 = [:] }
            if (e["error"] as? String) == "rate_limit" {
                // 限流 / 额度用完：额度那行变红，她回到「累了」；下一轮正常做完时 readUsage 会换掉这行
                HookOut.write("grok-quota.json", ["text": "Grok 额度用完了，等一会儿再试", "low": true])
                HookOut.setState(sid, "tired", "Stop", "", now)
            } else {
                HookOut.setState(sid, "oops", "Stop", "", now)
            }
            HookOut.notify(rawSid, "error")
        case "StopCancelled":
            HookOut.turn(sid) { $0 = [:] }
            // 你按了 Ctrl+C / 拒绝了授权：吓一跳；它自己放弃的（max_turns、no_progress……）：出错
            let byUser = (e["cancelledBy"] as? String ?? e["cancelled_by"] as? String) == "user"
            HookOut.setState(sid, byUser ? "surprised" : "oops", "Stop", "", now)
            readUsage(dir)
        case "PreCompact":
            HookOut.setState(sid, "compact", "PreCompact", "", now)
        case "PostCompact":
            if (e["trigger"] as? String) == "manual" { HookOut.setState(sid, "happy", "Stop", "", now) }
            else { HookOut.setState(sid, "thinking", "PostCompact", "", now) }
        case "SessionEnd":
            if e["subagentType"] != nil || e["subagent_type"] != nil { break }   // 子代理的会话结束，主会话还在
            HookOut.removeSession(sid)
        default:
            break
        }
    }

    // ---------------- 额度（其实是花费） ----------------
    /// 会话文件夹 ~/.grok/sessions/<cwd 做 URL 编码>/<会话 id>/（transcript_path 就在里面；SessionStart 不带 transcript_path，自己拼）：
    ///   usage.json    {"session": {"costUsdTicks": …}}   1 美元 = 1e10 ticks（grok -p 的 total_cost_usd_ticks 和 total_cost_usd 对过）
    ///   signals.json  {"contextWindowUsage": 36, …}      上下文用了百分之几
    static func readUsage(_ dir: URL?) {
        guard let dir, let q = quota(sessionDir: dir) else { return }
        HookOut.write("grok-quota.json", q)
    }

    static func sessionDir(_ e: [String: Any], _ sid: String) -> URL? {
        if let t = e["transcript_path"] as? String { return URL(fileURLWithPath: t).deletingLastPathComponent() }
        guard let cwd = e["cwd"] as? String,
              let folder = cwd.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "-._~").union(.alphanumerics)) else { return nil }
        return GrokIntegration.grokHome.appendingPathComponent("sessions").appendingPathComponent(folder).appendingPathComponent(sid)
    }

    static func quota(sessionDir dir: URL) -> [String: Any]? {
        var parts: [String] = []
        if let session = Store.readJSON(dir.appendingPathComponent("usage.json"))?["session"] as? [String: Any],
           let ticks = (session["costUsdTicks"] as? NSNumber)?.doubleValue {
            let usd = ticks / 1e10
            parts.append("本次会话 " + (usd > 0 && usd < 0.01 ? "<$0.01" : String(format: "$%.2f", usd)))
        }
        if let ctx = (Store.readJSON(dir.appendingPathComponent("signals.json"))?["contextWindowUsage"] as? NSNumber)?.intValue {
            parts.append("上下文 \(ctx)%")
        }
        // 不给 bars：网页按 bars 演「钱袋」动画（剩多少额度），这里没有剩余额度可演
        return parts.isEmpty ? nil : ["text": parts.joined(separator: " · "), "low": false]
    }
}

// ---------------- 接入 Grok ----------------
/// 写一个只归我们的文件：~/.grok/hooks/claudia-pet.json（有 GROK_HOME 就用它）。撤销就是删掉它，不碰别的 hook。
/// 用户目录里的 hooks 不用信任，新开的 grok 会话就生效。
/// 不能写进 ~/.claude/settings.json：grok 也读那里的 hooks，Claude Code 和 grok 会各收一份。
enum GrokIntegration {
    static let events = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                         "PermissionDenied", "Notification", "SubagentStart", "SubagentStop", "Stop", "StopFailure", "StopCancelled",
                         "PreCompact", "PostCompact"]
    static var grokHome: URL { Store.env("GROK_HOME").map { URL(fileURLWithPath: $0) } ?? Store.home.appendingPathComponent(".grok") }
    static var hooksFile: URL { grokHome.appendingPathComponent("hooks/claudia-pet.json") }

    static var installed: Bool {
        guard let hooks = Store.readJSON(hooksFile)?["hooks"] as? [String: Any] else { return false }
        return !hooks.isEmpty
    }

    static var seenText: String { HookOut.seenText("grok", name: "Grok", installed: installed, hint: "（新开一个 grok 会话试试）") }

    static func toggle(install: Bool) {
        var message: String
        do { message = try set(install: install) } catch { message = "没有完成：\(error.localizedDescription)" }
        Store.log("接入 Grok \(install)：\(message)")
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "接入 Grok"; a.informativeText = message; a.runModal()
    }

    static func set(install: Bool) throws -> String {
        let fm = FileManager.default, file = hooksFile
        if !install {
            guard fm.fileExists(atPath: file.path) else { return "本来就没有接入。" }
            try fm.removeItem(at: file)
            return "已撤销 Grok 接入。\n\n删了：\(file.path)"
        }
        HookOut.refreshLink()
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [["hooks": [["type": "command", "command": HookOut.command("grok"), "timeout": 5]]]]
        }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Store.writeJSON(file, ["hooks": hooks])
        var msg = "已接入 Grok，新开的 grok 会话生效。\n\n写了：\(file.path)（只归 claudia-pet，撤销时整个删掉）"
        // 在 grok 的 /hooks 里按空格关掉过的 hook 记在 disabled-hooks（名字像 global/claudia-pet:stop[0].hooks[0]）
        if let off = try? String(contentsOf: grokHome.appendingPathComponent("disabled-hooks"), encoding: .utf8), off.contains("claudia-pet") {
            msg += "\n\n注意：你在 grok 的 /hooks 里关掉过其中几条（记在 ~/.grok/disabled-hooks），要在那里重新打开。"
        }
        if let req = try? String(contentsOfFile: "/etc/grok/requirements.toml", encoding: .utf8),
           req.range(of: #"(?m)^\s*allow_managed_hooks_only\s*=\s*true"#, options: .regularExpression) != nil {
            msg += "\n\n注意：这台电脑的管理策略只允许公司下发的 hooks（allow_managed_hooks_only），这几条不会运行。"
        }
        return msg
    }
}
