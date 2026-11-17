import Carbon.HIToolbox

/// 全局快捷键 ⌃⌥P：暂时隐藏 / 再按一次显示。用 Carbon 的 RegisterEventHotKey，不需要辅助功能权限。
final class Hotkey {
    static let shared = Hotkey()
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    /// 返回是否注册成功（被别的程序占用时会失败）
    func register() -> Bool {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { Hotkey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x434C_4450 /* CLDP */), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }
    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
