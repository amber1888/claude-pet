import AppKit
import WebKit

/// 桌宠窗口：无边框、透明、不抢焦点、所有桌面空间都在。
final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true   // 平时点击穿过去；鼠标移到桌宠身上时由 Pet 打开
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 网页本身不处理鼠标：单击、拖动、右键都在这里接住，交给 Pet（和 Windows 版的外壳一样）
protocol PetMouse: AnyObject {
    func petMouseDown(_ e: NSEvent)
    func petMouseDragged(_ e: NSEvent)
    func petMouseUp(_ e: NSEvent)
    func petRightMouse(_ e: NSEvent)
    func petHit(_ pointInView: NSPoint) -> Bool
}

final class PetWebView: WKWebView {
    weak var mouse: PetMouse?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), mouse?.petHit(local) ?? false else { return nil }
        return self
    }
    override func mouseDown(with e: NSEvent) { mouse?.petMouseDown(e) }
    override func mouseDragged(with e: NSEvent) { mouse?.petMouseDragged(e) }
    override func mouseUp(with e: NSEvent) { mouse?.petMouseUp(e) }
    override func rightMouseDown(with e: NSEvent) { mouse?.petRightMouse(e) }
    override func rightMouseUp(with e: NSEvent) {}
    override func otherMouseDown(with e: NSEvent) {}
    override func scrollWheel(with e: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {}
}
