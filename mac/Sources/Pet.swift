import AppKit
import WebKit
import UserNotifications

/// 桌宠本体：透明窗口承载 web/index.html（和 Windows 版共用的网页：动画、物理、台词、情绪都在网页里），
/// 这里只做外壳的事——摆窗口、接鼠标、读 Claude Code 插件写的状态文件、菜单、通知。
///
/// 坐标约定（和网页、Windows 版一致）：屏幕坐标，原点在主屏左上角，y 向下，单位是点（pt）。
final class Pet: NSObject, PetMouse, WKScriptMessageHandler, WKNavigationDelegate, NSMenuDelegate {
    static let baseW: CGFloat = 260, baseH: CGFloat = 362

    let window: PetPanel
    let web: PetWebView
    private let resources = ResourceHandler()
    private var ready = false
    private var manifest: [String: Any] = [:]
    private var pageW: CGFloat = baseW, pageH: CGFloat = baseH
    private var statusItem: NSStatusItem?
    private var timers: [Timer] = []
    private(set) var userHidden = false
    private var quitting = false

    override init() {
        let s = CGFloat(Pet.scale)
        window = PetPanel(size: NSSize(width: Pet.baseW * s, height: Pet.baseH * s))
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(resources, forURLScheme: Store.scheme)
        config.suppressesIncrementalRendering = true
        // 网页按 window.chrome.webview.postMessage 给外壳发消息（WebView2 的写法）：这里接到 WKWebView 上
        let shim = """
        window.chrome = window.chrome || {};
        window.chrome.webview = { postMessage: function (m) { try { window.webkit.messageHandlers.host.postMessage(JSON.stringify(m)) } catch (e) {} } };
        """
        config.userContentController.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = PetWebView(frame: NSRect(origin: .zero, size: window.frame.size), configuration: config)
        super.init()
        config.userContentController.add(WeakHandler(self), name: "host")
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.pageZoom = s
        web.mouse = self
        web.navigationDelegate = self
        web.autoresizingMask = [.width, .height]
        window.contentView = web
    }

    func start() {
        restorePosition()
        window.orderFrontRegardless()
        web.load(URLRequest(url: URL(string: "\(Store.origin)/index.html")!))
        setupStatusItem()
        startDebugHook()
        Hotkey.shared.onPress = { [weak self] in self?.toggleHidden() }
        applyHotkey()
        timers.append(every(0.3) { [weak self] in self?.poll() })
        timers.append(every(1.0 / 30) { [weak self] in self?.updatePassThrough() })
        let ws = NSWorkspace.shared.notificationCenter
        for (n, hidden) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
                            (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.systemHidden = hidden; self.updatePageHidden()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keepOnScreen()
        }
    }

    private func every(_ s: TimeInterval, _ f: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: s, repeats: true) { _ in f() }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    // ---------------- 和网页打交道 ----------------
    func js(_ code: String) {
        guard ready || code.hasPrefix("init(") else { return }
        web.evaluateJavaScript(code) { _, err in
            if let err { Store.log("JS 出错: \(err.localizedDescription) — \(code.prefix(120))") }
        }
    }
    static func q(_ s: String) -> String { Store.json(s) }
    static func num(_ d: Double) -> String { d.isFinite ? String(format: "%.3f", d) : "0" }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = false
        manifest = Store.manifest(customName: Store.defaults.string(forKey: "name"))
        let script = "init(\(Store.json(manifest))); setCharacter('claude', true); setAuraMode(\(Pet.q(Pet.auraMode))); "
            + "setShowName(\(Pet.showName)); setPowerSave(\(Store.flag("powerSave", false))); setQuotaStyle(\(Pet.q(Pet.quotaStyle))); "
            + "setBehavior(\(Store.json(behaviorState)))"
        web.evaluateJavaScript(script) { [weak self] _, err in
            guard let self else { return }
            if let err { Store.log("初始化网页失败: \(err)") }
            self.ready = true
            self.stamps.removeAll()
            self.applySizes(anchor: .corner)
            self.updatePageHidden()
            self.poll()
            if Store.defaults.string(forKey: "lastVersion") != Store.version {
                Store.defaults.set(Store.version, forKey: "lastVersion")
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Store.log("网页进程退出，重新加载")
        ready = false
        stopMotion(save: false)
        webView.reload()
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let s = message.body as? String, let d = s.data(using: .utf8),
              let m = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        if let r = m["hitRects"] as? [[Double]] { hitRects = r.filter { $0.count == 4 }; return }
        if let mm = m["motion"] as? [String: Any] { acceptMotion(mm); return }
        if m.keys.contains("walk") { handleWalk(m["walk"] as? [String: Any]); return }
        if let e = m["jsError"] { Store.log("网页脚本出错: \(e)"); return }
        if let e = m["imageError"] { Store.log("立绘加载失败: \(e)") }
    }

    // ---------------- 大小 ----------------
    static var scale: Double { Store.number("size", 1.0, 0.6, 1.6) }
    enum Anchor { case corner, bottom }
    func applySizes(anchor: Anchor) {
        let s = Pet.scale
        web.evaluateJavaScript("setSizes(\(Pet.num(s)), \(Pet.num(s)), true)") { [weak self] r, _ in
            guard let self else { return }
            if let str = r as? String, let d = str.data(using: .utf8),
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                self.pageW = CGFloat((o["w"] as? Double) ?? Double(Pet.baseW))
                self.pageH = CGFloat((o["h"] as? Double) ?? Double(Pet.baseH))
            }
            let old = self.window.frame
            let size = NSSize(width: (self.pageW * CGFloat(s)).rounded(), height: (self.pageH * CGFloat(s)).rounded())
            var origin = old.origin
            switch anchor {
            case .corner: origin.y = old.maxY - size.height                       // 左上角不动
            case .bottom: origin.x = old.midX - size.width / 2                     // 底边中点不动
            }
            self.web.pageZoom = CGFloat(s)
            self.window.setFrame(NSRect(origin: origin, size: size), display: true)
            self.keepOnScreen()
        }
    }

    // ---------------- 位置 ----------------
    private var top: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    private func webPos() -> (x: Double, y: Double) { (Double(window.frame.minX), Double(top - window.frame.maxY)) }
    private func moveTo(x: Double, y: Double) {
        let o = NSPoint(x: CGFloat(x), y: top - CGFloat(y) - window.frame.height)
        if o != window.frame.origin { window.setFrameOrigin(o) }
    }
    private func screenOfPet() -> NSScreen? {
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(c) } ?? window.screen ?? NSScreen.main
    }
    /// 活动范围（网页坐标）：所在显示器的可用区域（不含菜单栏、程序坞），整个窗口都要在里面
    private func area() -> [String: Double]? {
        guard let vf = screenOfPet()?.visibleFrame else { return nil }
        let w = window.frame.width, h = window.frame.height
        let minX = Double(vf.minX), minY = Double(top - vf.maxY)
        return ["minX": minX, "minY": minY,
                "maxX": max(minX, Double(vf.maxX - w)), "maxY": max(minY, Double(top - vf.minY - h))]
    }
    func savePosition() {
        let p = webPos()
        Store.defaults.set(p.x, forKey: "posX"); Store.defaults.set(p.y, forKey: "posY")
    }
    private func restorePosition() {
        if Store.defaults.object(forKey: "posX") != nil {
            moveTo(x: Store.defaults.double(forKey: "posX"), y: Store.defaults.double(forKey: "posY"))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame.insetBy(dx: 40, dy: 40)) }) { keepOnScreen(); return }
        }
        recenter()
    }
    /// 回到默认位置：主屏右下角
    func recenter() {
        stopMotion(save: false); stopWalk(nil)
        guard let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: vf.maxX - window.frame.width - 40, y: vf.minY))
        savePosition()
    }
    private func keepOnScreen() {
        guard !dragging, !flying, let a = area() else { return }
        let p = webPos()
        let x = min(a["maxX"]!, max(a["minX"]!, p.x)), y = min(a["maxY"]!, max(a["minY"]!, p.y))
        if x != p.x || y != p.y { moveTo(x: x, y: y) }
    }

    // ---------------- 能点到的区域：其余透明的地方让点击穿过去 ----------------
    private var hitRects: [[Double]] = []
    private var pressed = false
    func petHit(_ p: NSPoint) -> Bool {
        if pressed || dragging { return true }
        let z = Double(web.pageZoom)
        let y = Double(web.isFlipped ? p.y : web.bounds.height - p.y) / z, x = Double(p.x) / z
        return hitRects.contains { x >= $0[0] && x <= $0[0] + $0[2] && y >= $0[1] && y <= $0[1] + $0[3] }
    }
    private func updatePassThrough() {
        guard window.isVisible, !pressed, !dragging else { return }
        let m = NSEvent.mouseLocation
        var over = false
        if window.frame.contains(m) {
            let local = web.convert(window.convertPoint(fromScreen: m), from: nil)
            over = petHit(local)
        }
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
    }

    // ---------------- 鼠标：单击摸头、拖动、甩、扔出去、右键菜单 ----------------
    private var down = NSPoint.zero
    private var dragging = false, flying = false
    private var motionId = 0
    private var dragT0: TimeInterval = 0
    private var lastMotionPos: (Int, Int)?

    var pointerOverride: NSPoint?   // 调试：模拟鼠标位置（网页坐标）
    private func pointer() -> NSPoint {
        if let p = pointerOverride { return p }
        let m = NSEvent.mouseLocation; return NSPoint(x: m.x, y: top - m.y)
    }

    func petMouseDown(_ e: NSEvent) { mouseDown() }
    func petMouseDragged(_ e: NSEvent) { mouseDragged(at: e.timestamp) }
    func mouseDown() {
        stopMotion()
        down = pointer(); pressed = true
    }
    func mouseDragged(at time: TimeInterval) {
        guard pressed else { return }
        let p = pointer()
        if !dragging {
            if abs(p.x - down.x) + abs(p.y - down.y) <= 4 { return }
            beginDrag(at: time)
            return
        }
        js("petMotion.pointer({id:\(motionId),px:\(Pet.num(p.x)),py:\(Pet.num(p.y)),time:\(Pet.num((time - dragT0) * 1000))})")
    }
    func petMouseUp(_ e: NSEvent) {
        let wasDragging = dragging
        pressed = false
        if wasDragging { endDrag(at: e.timestamp); return }
        let local = web.convert(e.locationInWindow, from: nil)
        let z = Double(web.pageZoom)
        let y = Double(web.isFlipped ? local.y : web.bounds.height - local.y) / z
        js("handleClick('pat', \(Pet.num(Double(local.x) / z)), \(Pet.num(y)))")
    }
    func petRightMouse(_ e: NSEvent) {
        pressed = false
        let menu = NSMenu()
        fillMenu(menu)
        NSMenu.popUpContextMenu(menu, with: e, for: web)
    }

    private var physicsConfig: [String: Any] {
        ["gravity": Store.number("gravity", 1400, 0, 3000), "restitution": 0.78, "groundFriction": 2.5,
         "throwPower": Store.number("throwPower", 1.0, 0.2, 2.5), "ceilingBounce": Store.flag("ceilingBounce"), "petCollision": false]
    }
    private func motionPacket() -> [String: Any]? {
        guard let b = area() else { return nil }
        return ["id": motionId, "bounds": b, "physics": physicsConfig, "enabled": Store.flag("physicsEnabled")]
    }
    private func beginDrag(at time: TimeInterval) {
        stopWalk(nil)
        stopMotion(save: false)
        guard ready, var packet = motionPacket() else { return }
        dragging = true; dragT0 = time; window.ignoresMouseEvents = false
        let p = webPos(), cur = pointer()
        packet["x"] = p.x; packet["y"] = p.y
        packet["downX"] = Double(down.x); packet["downY"] = Double(down.y)
        packet["px"] = Double(cur.x); packet["py"] = Double(cur.y); packet["time"] = 0
        js("setMotionActive(true); petMotion.begin(\(Store.json(packet)))")
    }
    func endDrag(at time: TimeInterval) {
        pressed = false
        guard dragging else { return }
        let cur = pointer(), t = (time - dragT0) * 1000
        js("petMotion.pointer({id:\(motionId),px:\(Pet.num(cur.x)),py:\(Pet.num(cur.y)),time:\(Pet.num(t))})")
        dragging = false; flying = true
        let p = webPos()
        js("petMotion.end({id:\(motionId),x:\(Pet.num(p.x)),y:\(Pet.num(p.y)),time:\(Pet.num(t))})")
    }
    func stopMotion(save: Bool = true) {
        let moved = dragging || flying
        motionId += 1; dragging = false; flying = false; lastMotionPos = nil
        if moved { js("petMotion.stop(); setMotionActive(false)") }
        if moved && save { savePosition() }
    }
    private func acceptMotion(_ m: [String: Any]) {
        guard (m["id"] as? Int) == motionId, dragging || flying, let phase = m["phase"] as? String else { return }
        if phase == "drag" && !dragging || phase == "flight" && !flying || phase == "end" && dragging { return }
        guard ["drag", "flight", "end"].contains(phase), let x = m["x"] as? Double, let y = m["y"] as? Double, x.isFinite, y.isFinite else { return }
        let pos = (Int(x.rounded()), Int(y.rounded()))
        if lastMotionPos == nil || lastMotionPos! != pos { moveTo(x: Double(pos.0), y: Double(pos.1)); lastMotionPos = pos }
        if phase == "end" { stopMotion(); return }
        if m["shake"] as? Bool == true { js("shaken()") }
        let ix = m["impactX"] as? Double ?? 0, iy = m["impactY"] as? Double ?? 0
        if max(ix, iy) > 120 { js("physicsImpact(\(Pet.num(ix)), \(Pet.num(iy)), 0.12)") }
    }

    // ---------------- 自己走路：网页定方向、速度（物理像素/秒）、走多久，这里逐帧平移窗口 ----------------
    private var walkTimer: Timer?
    private var walkDir = 0.0, walkSpeed = 0.0, walkX = 0.0
    private var walkUntil: TimeInterval = 0, walkLast: TimeInterval = 0

    private func handleWalk(_ w: [String: Any]?) {
        guard let w else { stopWalk(nil); return }
        guard let dir = w["dir"] as? Double, let speed = w["speed"] as? Double, let ms = w["ms"] as? Double,
              speed > 0, speed <= 4000, ms > 0, ms <= 60000, dir == 1 || dir == -1 else { return }
        stopWalk(nil)
        guard !dragging, !flying, !userHidden, let a = area() else { js("walkEnded('blocked')"); return }
        let x = webPos().x
        let room = dir < 0 ? x - a["minX"]! : a["maxX"]! - x
        if room < 24 { js("walkEnded('blocked')"); return }
        walkDir = dir; walkSpeed = speed / Double(window.backingScaleFactor); walkX = x
        walkLast = ProcessInfo.processInfo.systemUptime; walkUntil = walkLast + ms / 1000
        walkTimer = every(1.0 / 60) { [weak self] in self?.walkFrame() }
    }
    private func walkFrame() {
        guard walkTimer != nil else { return }
        if dragging || flying { stopWalk(nil); return }
        guard !userHidden, let a = area() else { stopWalk("done"); return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, now - walkLast); walkLast = now
        walkX += walkDir * walkSpeed * dt
        var edge = false
        if walkX <= a["minX"]! { walkX = a["minX"]!; edge = true }
        if walkX >= a["maxX"]! { walkX = a["maxX"]!; edge = true }
        moveTo(x: walkX.rounded(), y: webPos().y)
        if edge { stopWalk("edge") } else if now >= walkUntil { stopWalk("done") }
    }
    private func stopWalk(_ reason: String?) {
        guard let t = walkTimer else { return }
        t.invalidate(); walkTimer = nil
        savePosition()
        if let reason { js("walkEnded('\(reason)')") }
    }

    // ---------------- 读 Claude Code 插件写的状态和额度 ----------------
    private var stamps: [String: String] = [:]
    private let notices = TaskNotices()

    private func poll() {
        guard ready else { return }
        let fm = FileManager.default
        for kind in ["state", "quota", "sessions"] {
            let file = Store.state.appendingPathComponent("claude-\(kind).json")
            guard let attr = try? fm.attributesOfItem(atPath: file.path), let mtime = attr[.modificationDate] as? Date,
                  let size = attr[.size] as? Int, size < 1_000_000 else { continue }
            let stamp = "\(mtime.timeIntervalSince1970):\(size)", key = "claude-\(kind)"
            if stamps[key] == stamp { continue }
            if kind == "state" && Date().timeIntervalSince(mtime) > 600 { stamps[key] = stamp; continue }   // 只认 10 分钟内的
            guard let value = Store.readJSON(file) else { continue }   // 可能正被写一半，下次再读
            stamps[key] = stamp
            let json = Store.json(value)
            switch kind {
            case "sessions": js("setSessions('claude', \(json))")
            case "state": js("applyCharState('claude', \(json))")
            default: js("setQuota('claude', \(json), \(Int(mtime.timeIntervalSince1970)))")
            }
        }
        pollNotices()
    }

    private func pollNotices() {
        let files = ((try? FileManager.default.contentsOfDirectory(at: Store.state, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("claude-notify-") && $0.pathExtension == "json" }
        for f in files {
            guard let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = v.contentModificationDate, let size = v.fileSize,
                  size < 100_000, Date().timeIntervalSince(mtime) < 120 else { continue }
            let key = "notice:" + f.path, stamp = "\(mtime.timeIntervalSince1970):\(size)"
            if stamps[key] == stamp { continue }
            guard let data = Store.readJSON(f), let events = data["events"] as? [[String: Any]] else { continue }
            stamps[key] = stamp
            for e in events {
                guard let id = e["id"] as? String, let kind = e["kind"] as? String, let ts = e["ts"] as? Double else { continue }
                taskNotice(id: id, kind: kind, ts: ts)
            }
        }
    }

    /// 前台是 Claude 桌面端或常见的终端 / 编辑器时，算你正看着 Claude Code
    private static let claudeFront: Set<String> = [
        "com.anthropic.claudefordesktop", "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]
    private func taskNotice(id: String, kind: String, ts: Double) {
        let enabled = Store.flag(kind == "waiting" ? "notifyWaiting" : "notifyResults")
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map { Pet.claudeFront.contains($0) } ?? false
        guard notices.accept(id: id, kind: kind, ts: ts, enabled: enabled, foreground: front,
                             backgroundOnly: Store.flag("notifyBackgroundOnly")) else { return }
        let title = kind == "waiting" ? "Claude 需要你确认" : kind == "error" ? "Claude 任务出错" : "Claude 任务已完成"
        let body = kind == "waiting" ? "有授权申请或问题等待你处理，回到 Claude 看一下吧。"
            : kind == "error" ? "这一轮未能正常完成，请回到 Claude 查看。" : "这一轮工作已结束，可以回到 Claude 查看结果。"
        Notifier.send(title: title, body: body)
    }

    // ---------------- 显示 / 隐藏 ----------------
    private var systemHidden = false
    private func updatePageHidden() { js("setPageHidden(\(userHidden || systemHidden))") }
    func setUserHidden(_ h: Bool) {
        userHidden = h
        if h { stopMotion(); stopWalk(nil); window.orderOut(nil) } else { window.orderFrontRegardless(); keepOnScreen() }
        updatePageHidden()
    }
    func toggleHidden() { setUserHidden(!userHidden) }

    /// 菜单里的「退出」：挥手道别再走；之后插件不会再自动把她叫出来，直到你自己打开
    func userQuit() {
        guard !quitting else { return }
        quitting = true
        try? FileManager.default.createDirectory(at: Store.data, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Store.userQuitFlag.path, contents: nil)
        stopMotion(); stopWalk(nil)
        if userHidden || !ready { NSApp.terminate(nil); return }
        js("farewell('', 2000)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { NSApp.terminate(nil) }
    }

    // ---------------- 菜单栏图标 ----------------
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(contentsOf: Store.resources.appendingPathComponent("AppIcon.png")) {
            img.size = NSSize(width: 20, height: 20)
            item.button?.image = img
        } else {
            item.button?.title = "🍊"
        }
        item.button?.toolTip = Store.appName
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }
    func menuNeedsUpdate(_ menu: NSMenu) { fillMenu(menu) }

    // ---------------- 设置 ----------------
    static var showName: Bool { Store.flag("showName") }
    static var auraMode: String { Store.string("auraMode", "auto", allowed: ["auto", "on", "off"]) }
    static var quotaStyle: String { Store.string("quotaStyle", "text", allowed: ["text", "bars"]) }
    var behaviorState: [String: Any] {
        ["idleEnabled": Store.flag("idleEnabled"), "idleFrequency": Store.string("idleFrequency", "normal", allowed: ["quiet", "normal", "lively"]),
         "clickBounce": Store.flag("clickBounce"), "tumbleActions": Store.flag("tumbleActions")]
    }
    func set(_ key: String, _ value: Any) {
        Store.defaults.set(value, forKey: key)
        switch key {
        case "size": applySizes(anchor: .bottom)
        case "showName": js("setShowName(\(Pet.showName))")
        case "auraMode": js("setAuraMode(\(Pet.q(Pet.auraMode)))")
        case "quotaStyle": js("setQuotaStyle(\(Pet.q(Pet.quotaStyle)))")
        case "powerSave": js("setPowerSave(\(Store.flag("powerSave", false)))")
        case "idleEnabled", "idleFrequency", "clickBounce", "tumbleActions": js("setBehavior(\(Store.json(behaviorState)))")
        case "physicsEnabled": if !(value as? Bool ?? true) { stopMotion() }
        case "hideHotkey": applyHotkey()
        default: break
        }
    }
    func rename(_ name: String) {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        if n.isEmpty { Store.defaults.removeObject(forKey: "name") } else { Store.defaults.set(n, forKey: "name") }
        manifest = Store.manifest(customName: Store.defaults.string(forKey: "name"))
        let shown = (manifest["characters"] as? [String: Any])?["claude"].flatMap { ($0 as? [String: Any])?["name"] as? String } ?? "claudia"
        js("setName('claude', \(Pet.q(shown)))")
    }
    var hotkeyFailed = false
    private func applyHotkey() {
        hotkeyFailed = Store.flag("hideHotkey") ? !Hotkey.shared.register() : { Hotkey.shared.unregister(); return false }()
    }

    // ---------------- 菜单 ----------------
    var actionPoses: Set<String> {
        guard let c = (manifest["characters"] as? [String: Any])?["claude"] as? [String: Any] else { return [] }
        var have = Set(((c["poses"] as? [String: Any]) ?? [:]).keys)
        let sheets = (c["sheets"] as? [String: Any]) ?? [:]
        for (k, v) in (c["animations"] as? [String: Any]) ?? [:] {
            guard let cfg = v as? [String: Any], cfg["hidden"] as? Bool != true else { continue }
            if ((cfg["sheets"] as? [String]) ?? []).contains(where: { sheets[$0] != nil }) { have.insert(k) }
        }
        return have
    }
    func playAction(_ pose: String) {
        guard pose.rangeOfCharacter(from: CharacterSet(charactersIn: "'\"\\\n\r")) == nil else { return }
        if userHidden { setUserHidden(false) }
        js("(function(p){ if (typeof show !== 'function') return; show(p, true);"
           + " clearTimeout(window.__claudiaMenuTimer);"
           + " if (typeof anim === 'function' && anim(p) && anim(p).walk && typeof startWalk === 'function' && startWalk(p)) return;"
           + " if (typeof anim === 'function' && anim(p) && transientMs(p)) return;"
           + " window.__claudiaMenuTimer = setTimeout(function(){ if (pose === p) show('idle', true); }, 6000); })('\(pose)')")
    }
}

/// WKUserContentController 会强引用消息处理者：隔一层，免得 Pet 永远释放不掉
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

/// 任务通知去重：同一事件只弹一次，太旧的、启动前的不弹，同类 8 秒内只弹一次（同 Windows 版 TaskNoticePolicy）
final class TaskNotices {
    private let started = Date().timeIntervalSince1970
    private var seen = Set<String>()
    private var shown: [String: Double] = [:]
    func accept(id: String, kind: String, ts: Double, enabled: Bool, foreground: Bool, backgroundOnly: Bool) -> Bool {
        let now = Date().timeIntervalSince1970
        guard !id.isEmpty, seen.insert(id).inserted else { return false }
        if seen.count > 2000 { seen = [id] }
        guard ["complete", "error", "waiting"].contains(kind), ts.isFinite, ts >= started, ts <= now + 5, now - ts <= 60 else { return false }
        guard enabled, !(backgroundOnly && foreground) else { return false }
        if let prev = shown[kind], now - prev < 8 { return false }
        shown[kind] = now
        return true
    }
}

enum Notifier {
    static func send(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { fallback(title, body); return }
        let c = UNUserNotificationCenter.current()
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { fallback(title, body); return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { err in
                if err != nil { fallback(title, body) }
            }
        }
    }
    /// 没有通知权限（没打包成 .app、或被拒绝）时退回 AppleScript 的通知
    private static func fallback(_ title: String, _ body: String) {
        let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(esc(body))\" with title \"\(esc(title))\""]
        try? p.run()
    }
}
