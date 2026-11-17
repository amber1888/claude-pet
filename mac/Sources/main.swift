import AppKit

// claudia-pet（macOS）：Claude 大小姐桌宠。
//   直接打开          出来；清掉「从菜单退出过」的标记
//   --ensure          Claude Code 插件叫她出来时用：你从菜单退出过就不出来，直到你自己再打开
let args = CommandLine.arguments
let fm = FileManager.default

if args.contains("--ensure") && fm.fileExists(atPath: Store.userQuitFlag.path) { exit(0) }
if !args.contains("--ensure") { try? fm.removeItem(at: Store.userQuitFlag) }

// 已经有一只在跑了：不再开第二只
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != NSRunningApplication.current }) {
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: Pet?
    func applicationDidFinishLaunching(_ n: Notification) {
        guard fm.fileExists(atPath: Store.web.appendingPathComponent("index.html").path),
              fm.fileExists(atPath: Store.characters.appendingPathComponent("claude/character.json").path) else {
            let a = NSAlert()
            a.messageText = "\(Store.appName) 缺少素材"
            a.informativeText = "没找到网页或角色立绘：\(Store.resources.path)\n请先运行 scripts/fetch-assets.sh，再用 scripts/build.sh 打包。"
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        Store.log("启动 \(Store.version)，资源：\(Store.resources.path)")
        pet = Pet()
        pet?.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    // 插件每次 open 都会触发「再次打开」：不在这里把暂时隐藏的她叫出来（用菜单栏图标或 ⌃⌥P）
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不进程序坞，只有菜单栏图标
app.run()
