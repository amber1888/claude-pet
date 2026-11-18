import AppKit
import WebKit

/// 开发自检（只在设置了 CLAUDIA_DEBUG_DIR 时启用）：
///   往 $CLAUDIA_DEBUG_DIR/cmd.js 写一段脚本 → 在网页里执行，结果写到 out.txt，再把画面截到 snap.png
extension Pet {
    func startDebugHook() {
        guard let dir = Store.env("CLAUDIA_DEBUG_DIR").map({ URL(fileURLWithPath: $0) }) else { return }
        let cmd = dir.appendingPathComponent("cmd.js")
        // 锁屏时也照常跑动画，方便自检（WebKit 的私有开关，只在调试时用）
        let sel = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        if web.responds(to: sel) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(web.method(for: sel), to: Setter.self)(web, sel, false)
        }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let code = try? String(contentsOf: cmd, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(at: cmd)
            if code.hasPrefix("#throw") { self.debugThrow(); return }
            if code.hasPrefix("#look ") {   // #look <形象 id>：和菜单里换形象一样；#look rescan 重新扫描
                let id = String(code.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if id == "rescan" { self.reloadLooks() } else { self.setLook(id) }
                try? "look=\(self.cid) looks=\(self.looks.map { "\($0.id):\($0.label)" })\n".write(to: dir.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
                return
            }
            if code.hasPrefix("#mail") {   // #mail check / #mail status：邮件提醒自检（结果写到 out.txt）
                Task { @MainActor in
                    let mc = MailCenter.shared
                    if code.contains("check") { mc.checkAll() }
                    if code.contains("keychain") {   // 钥匙串存、取、删一遍
                        let k = "selftest@claudia-pet.local"
                        let err = MailKeychain.set(k, "pw-123"); let got = MailKeychain.get(k); MailKeychain.remove(k)
                        try? "keychain setErr=\(err ?? "none") get=\(got ?? "nil") afterRemove=\(MailKeychain.get(k) ?? "nil")\n".write(to: dir.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
                        return
                    }
                    let text = mc.watchers.map { "\($0.account.email): \($0.status) \($0.unread.map { "\($0.from)|\($0.subject)" })" }.joined(separator: "\n")
                    try? "\(text)\nsummary=\(Store.json(mc.summary))\n".write(to: dir.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
                }
                return
            }
            if code.hasPrefix("#grok ") {   // #grok install / #grok uninstall
                let install = code.contains("uninstall") == false
                let text = (try? GrokIntegration.set(install: install)) ?? "失败"
                try? "\(text)\ninstalled=\(GrokIntegration.installed)\n".write(to: dir.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
                return
            }
            if code.hasPrefix("#codex ") {   // #codex install / #codex uninstall：不弹窗，结果写到 out.txt
                let install = code.contains("uninstall") == false
                let text = (try? CodexIntegration.set(install: install)) ?? "失败"
                try? "\(text)\ninstalled=\(CodexIntegration.installed)\n".write(to: dir.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
                return
            }
            self.web.evaluateJavaScript(code) { r, err in
                let text = err.map { "ERROR: \($0)" } ?? "\(r ?? "undefined")"
                let frame = self.window.frame
                try? (text + "\nwindow=\(frame) visible=\(self.window.isVisible) ignoresMouse=\(self.window.ignoresMouseEvents) occlusionVisible=\(self.window.occlusionState.contains(.visible)) screenAsleep=\(CGDisplayIsAsleep(CGMainDisplayID()))\n")
                    .write(to: dir.appendingPathComponent("out.txt"), atomically: true, encoding: .utf8)
                self.web.takeSnapshot(with: nil) { img, _ in
                    guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    try? png.write(to: dir.appendingPathComponent("snap.png"))
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    /// 模拟一次「按住 → 快速往左上甩 → 松手」，走和真鼠标一样的路径
    func debugThrow() {
        let f = window.frame, top = NSScreen.screens.first!.frame.maxY
        var p = NSPoint(x: f.midX, y: top - f.midY)
        pointerOverride = p
        mouseDown()
        let t0 = ProcessInfo.processInfo.systemUptime
        for i in 1...8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016 * Double(i)) {
                p.x -= 30; p.y -= 22
                self.pointerOverride = p
                self.mouseDragged(at: t0 + 0.016 * Double(i))
                if i == 8 { self.endDrag(at: t0 + 0.016 * 8.5); self.pointerOverride = nil }
            }
        }
    }
}
