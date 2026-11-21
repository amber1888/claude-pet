import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 找 Claude Code 的输入框在终端窗口里的确切位置：只截那一个终端窗口（不含桌宠），找最下面一对细横线——
/// Claude Code 的输入框上下各一条横线（老版本是圆角框的上下边），一样长、一样颜色，中间隔一两行字。
/// 横线两头就是终端那一栏的左右边，她在这个范围里蹦。
/// 要「屏幕录制」权限（macOS 14 起用 ScreenCaptureKit 截单个窗口）；没给就不找，Perch 退回按窗口底边估。
enum InputBox {
    /// 在窗口里的位置（点，从窗口左上角量）
    struct Found: Equatable { var top, bottom, left, right: Double }

    static var allowed: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult static func request() -> Bool { CGRequestScreenCaptureAccess() }

    // ---------------- 在截图里找 ----------------
    private struct Line { var y: Double; var x0, x1: Int; var r, g, b: Int }

    /// scale：图里几个像素一个点
    static func find(_ img: CGImage, scale: Double) -> Found? {
        let W = img.width, H = img.height
        guard W >= 200, H >= 80, scale > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: W * H * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
            return true
        }
        guard ok else { return nil }
        let lines: [Line] = buf.withUnsafeBufferPointer { p in scanLines(p, W, H, scale) }
        return pair(lines, scale)
    }

    /// 每一行找最长的「细横线」：这一点和上下各隔 2 点的地方颜色都不一样，而上下两处彼此差不多（背景）。
    /// 字的笔画连不成长线；大色块（状态栏、选中高亮）上下也是同一种颜色，不算细线。
    private static func scanLines(_ p: UnsafeBufferPointer<UInt8>, _ W: Int, _ H: Int, _ scale: Double) -> [Line] {
        let d = max(2, Int((2 * scale).rounded()))
        let gapMax = max(3, Int((3 * scale).rounded()))       // 横线字符之间可能有一两点的缝
        let minRun = max(Int(160 * scale), W * 3 / 10)
        @inline(__always) func diff(_ a: Int, _ b: Int) -> Int {
            max(abs(Int(p[a]) - Int(p[b])), abs(Int(p[a + 1]) - Int(p[b + 1])), abs(Int(p[a + 2]) - Int(p[b + 2])))
        }
        var rows: [Line] = []
        for y in max(d, H / 5) ..< (H - d) {
            var start = -1, last = -1000, best0 = 0, best1 = -1
            let row = y * W * 4, up = (y - d) * W * 4, dn = (y + d) * W * 4
            for x in 0 ..< W {
                let c = row + x * 4, u = up + x * 4, v = dn + x * 4
                if diff(u, v) < 26 && diff(c, u) > 20 && diff(c, v) > 20 {
                    if start < 0 || x - last > gapMax { start = x }
                    last = x
                    if x - start > best1 - best0 { best0 = start; best1 = x }
                }
            }
            guard best1 - best0 >= minRun else { continue }
            let m = row + ((best0 + best1) / 2) * 4
            rows.append(Line(y: Double(y), x0: best0, x1: best1, r: Int(p[m]), g: Int(p[m + 1]), b: Int(p[m + 2])))
        }
        // 相邻几行是同一条线（线有一两个像素粗，上下隔 d 的判断也会让它在附近多命中几行）
        var merged: [Line] = []
        var group: [Line] = []
        func flush() {
            guard !group.isEmpty else { return }
            let mid = group[group.count / 2]
            merged.append(Line(y: group.map(\.y).reduce(0, +) / Double(group.count), x0: group.map(\.x0).min()!, x1: group.map(\.x1).max()!,
                               r: mid.r, g: mid.g, b: mid.b))
            group = []
        }
        for l in rows {
            if let g = group.last, l.y - g.y > Double(d) { flush() }
            group.append(l)
        }
        flush()
        return merged
    }

    /// 最下面一对：两条线左右基本重合、颜色差不多、中间隔 12～240 点
    private static func pair(_ lines: [Line], _ scale: Double) -> Found? {
        let sorted = lines.sorted { $0.y > $1.y }
        for (i, b) in sorted.enumerated() {
            for a in sorted[(i + 1)...] {
                let gap = (b.y - a.y) / scale
                if gap < 12 { continue }
                if gap > 240 { break }
                let overlap = Double(min(a.x1, b.x1) - max(a.x0, b.x0)), longer = Double(max(a.x1 - a.x0, b.x1 - b.x0))
                let color = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
                guard overlap >= longer * 0.8, color <= 40 else { continue }
                return Found(top: a.y / scale, bottom: b.y / scale, left: Double(min(a.x0, b.x0)) / scale, right: Double(max(a.x1, b.x1)) / scale)
            }
        }
        return nil
    }

    // ---------------- 截终端窗口 ----------------
    private final class Done: @unchecked Sendable {
        let f: (Found?) -> Void
        init(_ f: @escaping (Found?) -> Void) { self.f = f }
    }

    /// 截 id 这个窗口（size：窗口大小，点）再找；在主线程回调，找不到 / 没权限 / 系统太旧都回 nil
    static func locate(window id: CGWindowID, size: CGSize, done: @escaping (Found?) -> Void) {
        guard allowed, #available(macOS 14.0, *) else { done(nil); return }
        let box = Done(done), w = size.width, h = size.height
        Task.detached(priority: .utility) {
            var found: Found?
            if let img = await shot(id, w, h) { found = find(img, scale: Double(img.width) / Double(w)) }
            let result = found
            DispatchQueue.main.async { box.f(result) }
        }
    }

    @available(macOS 14.0, *)
    private static func shot(_ id: CGWindowID, _ w: CGFloat, _ h: CGFloat) async -> CGImage? {
        guard w >= 100, h >= 60,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let win = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let cfg = SCStreamConfiguration()
        cfg.width = Int(w * 2); cfg.height = Int(h * 2)   // 按 2 倍截：细线在 1 倍下会糊成半透明
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg)
    }
}
