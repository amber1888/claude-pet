import AppKit
import CoreGraphics

/// 站在 Claude Code 的输入框上：你在终端里和 Claude（Codex、Grok 也算）说话时，她跳到那个终端窗口的输入框上陪着，
/// 跟着窗口挪，按会话里发生的事在输入框上蹦：
///   你发消息      原地一跳（接住了）
///   干活中        隔一会儿沿着输入框蹦到另一个地方
///   等你授权/回答 连着蹦两下，没理她就过几秒再蹦（提醒你）
///   完成          高高一跳；干了一大票（得意）连跳两下
///   出错          往后一个小趔趄
/// 你切到别的程序，她跳回原来的位置；从输入框上拖走她，下次你发消息之前不再跳回去；
/// 把她拖到输入框上放下，就记住这个终端里输入框在哪（每种终端各记一份）。
///
/// 怎么知道是哪个窗口：你发消息那一刻在最前面的程序的最前面的窗口（终端可能是 Terminal、iTerm、Ghostty、Orca、VS Code……，
/// 进程树也不一定连得到——tmux、Orca 的终端都挂在后台进程下面，所以不按进程找）。
/// 只用 CGWindowList 读窗口的位置、属于哪个进程，不用辅助功能、屏幕录制权限。输入框的高度没法直接知道，
/// 默认按 Claude Code 的布局估（窗口底边往上 58 点），对不上就拖她过去放一次。
///
/// 坐标都是网页坐标：原点在主屏左上角，y 向下（CGWindowList 的 bounds 正好也是这样）。
final class Perch {
    private unowned let pet: Pet
    init(pet: Pet) { self.pet = pet }

    static var enabled: Bool { Store.flag("perchEnabled") }
    static let defaultBottom = 58.0

    private var targetPid: pid_t = 0, targetWin: CGWindowID = 0, targetBundle = ""
    private var lastEvent = Date.distantPast
    private var suppressed = false            // 被拖走了：下次你发消息前不再跳回去
    private(set) var active = false           // 站在输入框上（或者正跳过去）
    private var rel = -150.0                  // 人物中心离窗口右边多远（负数）
    private var lastWin: CGRect?
    private var home: CGPoint?                // 跳上去之前在哪（窗口左上角），切走时跳回去
    private var feet = CGPoint(x: 130, y: 300) // 脚底中心在桌宠窗口里的位置（点，从左上角量），网页量好后交过来
    private var timer: Timer?
    var debugRect: CGRect? { didSet { if debugRect != nil { targetPid = 1; targetWin = 1; targetBundle = "debug"; suppressed = false } } }   // 调试：假的终端窗口
    var debugStatus: String { "active=\(active) hopping=\(hop != nil) suppressed=\(suppressed) target=\(targetBundle)#\(targetWin) rel=\(rel) bottom=\(bottom) feet=\(feet) win=\(lastWin.map { "\($0)" } ?? "nil") home=\(home.map { "\($0)" } ?? "nil")" }

    private struct Hop { var from, to: CGPoint; var t0: TimeInterval; var dur, height: Double; var then: (() -> Void)? }
    private var hop: Hop?
    private var hopTimer: Timer?
    var hopping: Bool { hop != nil }

    private var working = false, asking = false
    private var nextFidget = Date.distantFuture, nextAskHop = Date.distantFuture
    private var lastArriveLine = Date.distantPast

    func start() {
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); timer = t
    }

    /// 网页量好的脚底位置（CSS 像素，已经乘了缩放交过来）
    func setFeet(x: Double, y: Double) {
        guard x.isFinite, y.isFinite, x > 0, y > 0 else { return }
        feet = CGPoint(x: x, y: y)
        if active, hop == nil, let w = lastWin { pet.moveTo(x: spot(w).x, y: spot(w).y) }
    }

    // ---------------- 会话事件（Pet.poll 读到新状态时交过来） ----------------
    func event(_ state: Any) {
        guard let s = state as? [String: Any] else { return }
        let ev = s["event"] as? String ?? "", pose = s["pose"] as? String ?? ""
        lastEvent = Date()
        if ev == "UserPromptSubmit" { captureTarget(); suppressed = false }
        asking = pose == "asking"
        working = ["thinking", "reading", "writing", "running", "searching", "delegating", "compact", "listening"].contains(pose)
        if working && nextFidget == .distantFuture { nextFidget = Date().addingTimeInterval(.random(in: 6...10)) }
        if !working { nextFidget = .distantFuture }
        nextAskHop = asking ? Date().addingTimeInterval(5) : .distantFuture
        guard active, hop == nil, !pet.walkingNow else { return }
        switch pose {
        case _ where ev == "UserPromptSubmit": inPlace(height: 30, dur: 0.38)
        case "asking": bounce(2)
        case "happy": inPlace(height: 54, dur: 0.55)
        case "proud": inPlace(height: 46, dur: 0.5) { [weak self] in self?.inPlace(height: 64, dur: 0.6) }
        case "surprised": inPlace(height: 38, dur: 0.4)
        case "oops", "sorry": sideways(by: 26, height: 14, dur: 0.36)
        default: break
        }
    }

    private func captureTarget() {
        if debugRect != nil { return }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let w = Perch.windows().first(where: { $0.pid == app.processIdentifier }) else { return }
        if app.processIdentifier != targetPid || w.id != targetWin { lastWin = nil }
        targetPid = app.processIdentifier; targetWin = w.id; targetBundle = app.bundleIdentifier ?? app.localizedName ?? ""
    }

    /// 屏幕上的普通窗口，前面的在前
    private static func windows() -> [(pid: pid_t, id: CGWindowID, rect: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? Int,
                  let id = w[kCGWindowNumber as String] as? Int, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: Any], let r = CGRect(dictionaryRepresentation: b as CFDictionary),
                  r.width >= 300, r.height >= 120 else { return nil }
            return (pid_t(pid), CGWindowID(id), r)
        }
    }

    /// 该站在哪个窗口上：开着、没被拖走、最近 30 分钟有过动静、那个终端在最前面而且最前面的就是那个窗口
    private func perchWindow() -> CGRect? {
        guard Perch.enabled, !suppressed, targetPid != 0,
              Date().timeIntervalSince(lastEvent) < 1800, let front = NSWorkspace.shared.frontmostApplication else { return nil }
        if let r = debugRect { return r }
        if front.processIdentifier == getpid() { return active ? lastWin : nil }   // 点了她的菜单、对话框：不动
        guard front.processIdentifier == targetPid,
              let w = Perch.windows().first(where: { $0.pid == targetPid }), w.id == targetWin else { return nil }
        return w.rect
    }

    // ---------------- 位置 ----------------
    private var bottom: Double {
        (Store.defaults.dictionary(forKey: "perchBottom")?[targetBundle] as? Double) ?? Perch.defaultBottom
    }
    private func relRange(_ w: CGRect) -> ClosedRange<Double> {
        let lo = -(Double(w.width) - 70), hi = -50.0
        return lo < hi ? lo...hi : hi...hi
    }
    private func spot(_ w: CGRect, rel r: Double? = nil) -> CGPoint {
        let range = relRange(w), rr = min(range.upperBound, max(range.lowerBound, r ?? rel))
        let cx = Double(w.maxX) + rr, fy = Double(w.maxY) - bottom
        return CGPoint(x: (cx - Double(feet.x)).rounded(), y: (fy - Double(feet.y)).rounded())
    }
    /// 站在输入框上时能走的范围（网页走路用）
    func walkBand() -> [String: Double]? {
        guard active, let w = lastWin else { return nil }
        let r = relRange(w), y = Double(pet.webOrigin.y)
        return ["minX": Double(spot(w, rel: r.lowerBound).x), "maxX": Double(spot(w, rel: r.upperBound).x), "minY": y, "maxY": y]
    }

    private func tick() {
        guard hop == nil, !pet.busyWithMouse, !pet.userHidden else { return }
        guard let w = perchWindow() else { if active { leave() }; return }
        if !active { arrive(w); return }
        if pet.walkingNow {   // 网页让她沿着输入框走：跟着她记下位置
            rel = Double(pet.webOrigin.x + feet.x - w.maxX); lastWin = w; return
        }
        lastWin = w
        let s = spot(w)
        pet.moveTo(x: Double(s.x), y: Double(s.y))
        let now = Date()
        if asking, now >= nextAskHop { nextAskHop = now.addingTimeInterval(6); bounce(2) }
        else if working, now >= nextFidget {
            nextFidget = now.addingTimeInterval(.random(in: 7...14))
            let r = relRange(w), span = min(r.upperBound - r.lowerBound, 420)
            var to = Double.random(in: (r.upperBound - span)...r.upperBound)
            if abs(to - rel) < 40 { to = rel + (rel - 80 < r.upperBound - span ? 80 : -80) }
            sideways(by: to - rel, height: 22, dur: 0.32 + min(0.35, abs(to - rel) / 900))
        }
    }

    private func arrive(_ w: CGRect) {
        pet.stopWalkNow()
        home = pet.webOrigin
        active = true; lastWin = w
        rel = min(relRange(w).upperBound, max(relRange(w).lowerBound, rel))
        let to = spot(w), from = pet.webOrigin
        let d = hypot(Double(to.x - from.x), Double(to.y - from.y))
        guard d > 4 else { return }
        jump(to: to, height: min(170, max(60, d * 0.3)), dur: min(0.95, 0.45 + d / 2600)) { [weak self] in
            guard let self, Date().timeIntervalSince(self.lastArriveLine) > 600 else { return }
            self.lastArriveLine = Date(); self.pet.js("perchSay('arrive')")
        }
    }

    private func leave() {
        if pet.walkingNow { pet.stopWalkNow() }   // 先停（还算站着，不会把这里记成原来的位置）
        active = false
        guard let h = home else { return }
        home = nil
        let from = pet.webOrigin, d = hypot(Double(h.x - from.x), Double(h.y - from.y))
        guard d > 4, NSScreen.screens.contains(where: { pet.screenRect($0).insetBy(dx: 30, dy: 30).contains(CGPoint(x: h.x + feet.x, y: h.y + feet.y)) }) else { return }
        jump(to: h, height: min(140, max(40, d * 0.22)), dur: min(0.85, 0.4 + d / 2800))
    }

    // ---------------- 跳 ----------------
    private func inPlace(height: Double, dur: Double, then: (() -> Void)? = nil) { jump(to: pet.webOrigin, height: height, dur: dur, then: then) }
    private func bounce(_ n: Int) {
        guard n > 0 else { return }
        inPlace(height: 24, dur: 0.3) { [weak self] in self?.bounce(n - 1) }
    }
    private func sideways(by dx: Double, height: Double, dur: Double) {
        guard let w = lastWin else { return }
        rel += dx
        let r = relRange(w); rel = min(r.upperBound, max(r.lowerBound, rel))
        jump(to: spot(w), height: height, dur: dur)
    }

    private func jump(to: CGPoint, height: Double, dur: Double, then: (() -> Void)? = nil) {
        guard !pet.busyWithMouse, !pet.userHidden else { return }
        hop = Hop(from: pet.webOrigin, to: to, t0: ProcessInfo.processInfo.systemUptime, dur: dur, height: height, then: then)
        pet.js("perchHop('up', \(Pet.num(dur)))")
        hopTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.hopFrame() }
        RunLoop.main.add(t, forMode: .common); hopTimer = t
    }
    private func hopFrame() {
        guard let h = hop else { hopTimer?.invalidate(); hopTimer = nil; return }
        let t = min(1, (ProcessInfo.processInfo.systemUptime - h.t0) / h.dur)
        let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2   // 水平方向两头慢中间快
        let x = Double(h.from.x) + Double(h.to.x - h.from.x) * e
        let y = Double(h.from.y) + Double(h.to.y - h.from.y) * t - h.height * 4 * t * (1 - t)
        pet.moveTo(x: x.rounded(), y: y.rounded())
        guard t >= 1 else { return }
        hop = nil; hopTimer?.invalidate(); hopTimer = nil
        pet.js("perchHop('land', 0)")
        h.then?()
    }

    /// 鼠标按住她：停在半空也不管了，交给拖拽
    func cancelHop() { hop = nil; hopTimer?.invalidate(); hopTimer = nil }

    /// 拖完放下（甩出去也算，落定后）：放在终端窗口靠下的地方就记住输入框高度、站在那儿；放到别处就先不跳回去
    func dropped() {
        cancelHop()
        guard Perch.enabled, targetPid != 0,
              let w = debugRect ?? Perch.windows().first(where: { $0.id == targetWin })?.rect else { if active { active = false; suppressed = true }; home = nil; return }
        let o = pet.webOrigin, fx = Double(o.x + feet.x), fy = Double(o.y + feet.y)
        let fromBottom = Double(w.maxY) - fy
        if fx > Double(w.minX), fx < Double(w.maxX), fromBottom >= 8, fromBottom <= min(260, Double(w.height) * 0.6) {
            var all = Store.defaults.dictionary(forKey: "perchBottom") ?? [:]
            all[targetBundle] = fromBottom.rounded(); Store.defaults.set(all, forKey: "perchBottom")
            if !active { home = home ?? CGPoint(x: Store.defaults.double(forKey: "posX"), y: Store.defaults.double(forKey: "posY")) }
            active = true; suppressed = false; lastWin = w; lastEvent = Date()
            rel = fx - Double(w.maxX)
            pet.js("perchSay('learned')")
        } else {
            if active { suppressed = true }
            active = false; home = nil
        }
    }

    /// 回到默认位置、隐藏：不再站着，等下次你发消息
    func reset() { cancelHop(); active = false; home = nil; suppressed = true }
}
