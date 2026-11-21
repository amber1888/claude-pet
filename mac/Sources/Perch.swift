import AppKit
import CoreGraphics

/// 站在 Claude Code 的输入框上：你在终端里和 Claude（Codex、Grok 也算）说话时，她跳到那个终端窗口的输入框上陪着，
/// 跟着窗口挪。她有两个站的地方：输入框上面（轮到你说话时）和输入框下面（窗口底边，Claude 干活时），按会话里发生的事上下跳：
///   你发消息      从输入框上跳下去（把话带给 Claude）
///   干活中        在下面隔一会儿蹦到另一处，或者跳上输入框探个头、过一两秒再跳下去
///   等你授权/回答 跳上输入框连着蹦两下，没理她就过几秒再蹦（提醒你）
///   完成          从下面高高跳上输入框；干了一大票（得意）上去后再跳一下
///   出错          往后一个小趔趄
/// 右键菜单里也能叫她跳上去 / 跳下去。你切到别的程序，她跳回原来的位置；从输入框上拖走她，下次你发消息之前不再跳回去；
/// 把她拖到输入框上（或者下面）放下，就记住这个终端里那一层在哪（每种终端各记一份）。
///
/// 怎么知道是哪个窗口：你发消息那一刻在最前面的程序的最前面的窗口（终端可能是 Terminal、iTerm、Ghostty、Orca、VS Code……，
/// 进程树也不一定连得到——tmux、Orca 的终端都挂在后台进程下面，所以不按进程找）。
/// 输入框在哪：给了「屏幕录制」权限就截那个终端窗口，找 Claude Code 输入框上下那两条横线（InputBox.swift），
/// 站的高度、左右能蹦的范围都按找到的来，输入框变高（多打了几行字）她也跟着挪；
/// 没给权限只用 CGWindowList 读窗口位置，按 Claude Code 的布局估（上面一层在窗口底边往上 58 点，下面一层 6 点），
/// 对不上就拖她过去放一次。
///
/// 坐标都是网页坐标：原点在主屏左上角，y 向下（CGWindowList 的 bounds 正好也是这样）。
final class Perch {
    private unowned let pet: Pet
    init(pet: Pet) { self.pet = pet }

    static var enabled: Bool { Store.flag("perchEnabled") }
    /// 截窗口找输入框：设置开着（默认开）而且给了屏幕录制权限
    static var precise: Bool { Store.flag("perchPrecise") && InputBox.allowed }
    enum Level { case top, below }
    /// 每层脚底离窗口底边多远：记在哪个设置里、默认多少
    private static let levelKey: [Level: (key: String, fallback: Double)] = [.top: ("perchBottom", 58), .below: ("perchBelow", 6)]

    private var targetPid: pid_t = 0, targetWin: CGWindowID = 0, targetBundle = ""
    private var lastEvent = Date.distantPast
    private var suppressed = false            // 被拖走了：下次你发消息前不再跳回去
    private(set) var active = false           // 站在输入框上（或者正跳过去）
    private var rel = -150.0                  // 人物中心离窗口右边多远（负数）
    private(set) var level = Level.top        // 现在站在哪层
    private var wanted = Level.top             // 按会话状态该站哪层（轮到你：上面；Claude 干活：下面）
    private var holdUntil = Date.distantPast  // 探头、你叫她换层、刚拖过去：这之前先不回 wanted
    private(set) var box: InputBox.Found?      // 截图找到的输入框（窗口里的位置）；nil 时按窗口底边估
    private var boxMisses = 0, boxAt = Date.distantPast, locating = false
    private var waitUntil = Date.distantPast   // 正在截图找输入框，找到再跳：这之前 tick 别把她直接挪过去
    private var lastWin: CGRect?
    private var home: CGPoint?                // 跳上去之前在哪（窗口左上角），切走时跳回去
    private var feet = CGPoint(x: 130, y: 300) // 脚底中心在桌宠窗口里的位置（点，从左上角量），网页量好后交过来
    private var timer: Timer?
    var debugRect: CGRect? { didSet { if debugRect != nil { targetPid = 1; targetWin = 1; targetBundle = "debug"; suppressed = false } else { box = nil } } }
    func debugSetBox(_ b: InputBox.Found?) { box = b }   // 调试：假的终端窗口
    var debugStatus: String { "active=\(active) hopping=\(hop != nil) suppressed=\(suppressed) target=\(targetBundle)#\(targetWin) rel=\(rel) level=\(level) wanted=\(wanted) box=\(box.map { "\($0)" } ?? "nil") top=\(offset(.top)) below=\(offset(.below)) feet=\(feet) win=\(lastWin.map { "\($0)" } ?? "nil") home=\(home.map { "\($0)" } ?? "nil")" }

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
        if working { wanted = .below } else if ["asking", "happy", "proud", "surprised", "idle"].contains(pose) { wanted = .top }
        if working && nextFidget == .distantFuture { nextFidget = Date().addingTimeInterval(.random(in: 6...10)) }
        if !working { nextFidget = .distantFuture }
        nextAskHop = asking ? Date().addingTimeInterval(5) : .distantFuture
        guard active, hop == nil, !pet.walkingNow else { return }
        if !working || ev == "UserPromptSubmit" { holdUntil = .distantPast }   // 干活中途的工具事件不打断探头、你叫她换的层
        // 跳之前先看一眼输入框现在在哪（刚发完消息、要你回答时，输入框的样子会变）；一秒内看过就不再看
        if Date().timeIntervalSince(boxAt) < 1 { react(ev, pose) } else {
            refreshBox(wait: true) { [weak self] in self?.react(ev, pose) }
        }
    }

    private func react(_ ev: String, _ pose: String) {
        guard active, hop == nil, !pet.walkingNow, !pet.busyWithMouse else { return }
        switch pose {
        case _ where ev == "UserPromptSubmit": level == .top ? to(.below, height: 26) : inPlace(height: 30, dur: 0.38)
        case "asking": up(height: 30) { [weak self] in self?.bounce(2) }
        case "happy": level == .below ? to(.top, height: 64, dur: 0.6) : inPlace(height: 54, dur: 0.55)
        case "proud": up(height: 52) { [weak self] in self?.inPlace(height: 64, dur: 0.6) }
        case "surprised": level == .below ? to(.top, height: 40) : inPlace(height: 38, dur: 0.4)
        case "oops", "sorry": sideways(by: 26, height: 14, dur: 0.36)
        default: if level != wanted, Date() >= holdUntil { to(wanted, height: 26) }
        }
    }

    private func captureTarget() {
        if debugRect != nil { return }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let w = Perch.windows().first(where: { $0.pid == app.processIdentifier }) else { return }
        if app.processIdentifier != targetPid || w.id != targetWin { lastWin = nil; box = nil; boxMisses = 0 }
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
    private func offset(_ l: Level) -> Double {
        let k = Perch.levelKey[l]!
        return (Store.defaults.dictionary(forKey: k.key)?[targetBundle] as? Double) ?? k.fallback
    }
    private func remember(_ l: Level, _ v: Double) {
        let k = Perch.levelKey[l]!.key
        var all = Store.defaults.dictionary(forKey: k) ?? [:]
        all[targetBundle] = v.rounded(); Store.defaults.set(all, forKey: k)
    }
    /// 左右能蹦的范围（屏幕坐标）：找到输入框就是横线两头（终端那一栏），没找到就是整个窗口
    private func lane(_ w: CGRect) -> (left: Double, right: Double) {
        if let b = box { return (Double(w.minX) + b.left, Double(w.minX) + b.right) }
        return (Double(w.minX), Double(w.maxX))
    }
    /// rel（人物中心离右头多远）的范围
    private func relRange(_ w: CGRect) -> ClosedRange<Double> {
        let l = lane(w), lo = -((l.right - l.left) - 70), hi = -50.0
        return lo < hi ? lo...hi : hi...hi
    }
    /// 这一层脚底踩在哪（屏幕 y）：上面一层踩着输入框的上边线；下面一层在下边线往下一点（状态行那里），不出窗口
    private func feetY(_ w: CGRect, _ l: Level) -> Double {
        if let b = box {
            return l == .top ? Double(w.minY) + b.top : min(Double(w.maxY) - 4, Double(w.minY) + b.bottom + 36)
        }
        return Double(w.maxY) - offset(l)
    }
    private func spot(_ w: CGRect, rel r: Double? = nil, level l: Level? = nil) -> CGPoint {
        let range = relRange(w), rr = min(range.upperBound, max(range.lowerBound, r ?? rel))
        let cx = lane(w).right + rr, fy = feetY(w, l ?? level)
        return CGPoint(x: (cx - Double(feet.x)).rounded(), y: (fy - Double(feet.y)).rounded())
    }

    /// 截图找一下输入框。wait：找到之前 tick 别动她（马上要按新位置跳）
    private func refreshBox(wait: Bool = false, then: (() -> Void)? = nil) {
        guard Perch.precise, debugRect == nil, let w = lastWin, !locating else { then?(); return }
        locating = true; boxAt = Date()
        if wait { waitUntil = Date().addingTimeInterval(1.5) }
        let win = targetWin
        InputBox.locate(window: win, size: w.size) { [weak self] f in
            guard let self else { return }
            self.locating = false; self.waitUntil = .distantPast
            if win == self.targetWin {
                if let f { self.box = f; self.boxMisses = 0 } else {
                    self.boxMisses += 1
                    if self.boxMisses >= 3 { self.box = nil }   // 连着几次找不到（Claude Code 退出了？）：退回按窗口估
                }
            }
            then?()
        }
    }
    /// 站在输入框上时能走的范围（网页走路用）
    func walkBand() -> [String: Double]? {
        guard active, let w = lastWin else { return nil }
        let r = relRange(w), y = Double(pet.webOrigin.y)
        return ["minX": Double(spot(w, rel: r.lowerBound).x), "maxX": Double(spot(w, rel: r.upperBound).x), "minY": y, "maxY": y]
    }

    private func tick() {
        guard hop == nil, !pet.busyWithMouse, !pet.userHidden, Date() >= waitUntil else { return }
        guard let w = perchWindow() else { if active { leave() }; return }
        if !active { arrive(w); return }
        let now = Date()
        if Perch.precise, !locating, now.timeIntervalSince(boxAt) > 3 { refreshBox() }   // 每 3 秒看一眼输入框挪没挪
        if pet.walkingNow {   // 网页让她沿着输入框走：跟着她记下位置
            rel = Double(pet.webOrigin.x + feet.x) - lane(w).right; lastWin = w; return
        }
        let windowMoved = lastWin != w
        lastWin = w
        let s = spot(w), cur = pet.webOrigin
        let off = hypot(Double(s.x - cur.x), Double(s.y - cur.y))
        if !windowMoved, off > 3 {   // 窗口没动、站的地方变了（输入框多了几行、刚找到输入框）：小跳过去，不瞬移
            jump(to: s, height: min(22, 6 + off * 0.2), dur: min(0.45, 0.24 + off / 600)); return
        }
        pet.moveTo(x: Double(s.x), y: Double(s.y))
        if asking, now >= nextAskHop { nextAskHop = now.addingTimeInterval(6); up(height: 30) { [weak self] in self?.bounce(2) } }
        else if level != wanted, now >= holdUntil { to(wanted, height: wanted == .top ? 40 : 22) }
        else if working, now >= nextFidget, level == .below {
            nextFidget = now.addingTimeInterval(.random(in: 7...14))
            if Double.random(in: 0..<1) < 0.35 {   // 跳上输入框探个头，一两秒后自己跳回去（上面那个分支）
                to(.top, height: 34); holdUntil = now.addingTimeInterval(.random(in: 1.4...2.6)); return
            }
            let r = relRange(w), span = min(r.upperBound - r.lowerBound, 420)
            var to = Double.random(in: (r.upperBound - span)...r.upperBound)
            if abs(to - rel) < 40 { to = rel + (rel - 80 < r.upperBound - span ? 80 : -80) }
            sideways(by: to - rel, height: 22, dur: 0.32 + min(0.35, abs(to - rel) / 900))
        }
    }

    private func arrive(_ w: CGRect) {
        pet.stopWalkNow()
        home = pet.webOrigin
        active = true; lastWin = w; level = wanted; holdUntil = .distantPast
        refreshBox(wait: true) { [weak self] in self?.arriveJump() }
    }
    private func arriveJump() {
        guard active, hop == nil, !pet.busyWithMouse, let w = lastWin else { return }
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
    /// 换一层：往上跳要跳得比目标高，往下是先小跳一下再落下去
    private func to(_ l: Level, height: Double, dur: Double? = nil, then: (() -> Void)? = nil) {
        guard let w = lastWin else { return }
        level = l
        let target = spot(w), dy = abs(Double(target.y) - Double(pet.webOrigin.y))
        jump(to: target, height: height, dur: dur ?? min(0.6, 0.34 + dy / 400), then: then)
    }
    /// 在下面就先跳上去再接着做，在上面直接做
    private func up(height: Double, then: @escaping () -> Void) {
        if level == .below { to(.top, height: height, then: then) } else { then() }
    }
    /// 右键菜单「跳到输入框下面 / 上面」：跳过去，待一会儿（30 秒内不按会话状态跳回去）
    func switchLevel() {
        guard active, hop == nil else { return }
        if pet.walkingNow { pet.stopWalkNow() }
        to(level == .top ? .below : .top, height: level == .top ? 26 : 44)
        holdUntil = Date().addingTimeInterval(30)
    }

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
        if box != nil {   // 找得到输入框：不用记高度，放在输入框附近就站过去（离哪层近站哪层）
            let top = feetY(w, .top), below = feetY(w, .below), l = lane(w)
            if fx > l.left - 40, fx < l.right + 40, fy > top - 120, fy < Double(w.maxY) + 10 {
                level = abs(fy - top) <= abs(fy - below) ? .top : .below
                holdUntil = Date().addingTimeInterval(20)
                if !active { home = home ?? CGPoint(x: Store.defaults.double(forKey: "posX"), y: Store.defaults.double(forKey: "posY")) }
                active = true; suppressed = false; lastWin = w; lastEvent = Date()
                rel = fx - l.right
            } else {
                if active { suppressed = true }
                active = false; home = nil
            }
            return
        }
        let fromBottom = Double(w.maxY) - fy
        if fx > Double(w.minX), fx < Double(w.maxX), fromBottom >= -4, fromBottom <= min(260, Double(w.height) * 0.6) {
            // 放得比上面一层的一半还高算上面（输入框上），否则算下面（窗口底边那一带）
            let l: Level = fromBottom >= max(20, offset(.top) * 0.6) ? .top : .below
            remember(l, fromBottom); level = l; holdUntil = Date().addingTimeInterval(20)
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
