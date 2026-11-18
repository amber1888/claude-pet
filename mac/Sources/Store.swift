import Foundation

/// 目录、设置、日志、角色清单。
/// 数据放 ~/.claudia（和 Windows 版一致）：Claude Code 插件往 ~/.claudia/state 写工作状态和额度。
enum Store {
    static let appName = "claudia-pet"
    static let bundleID = "local.claudia-pet.mac"

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static let data: URL = env("CLAUDIA_DATA_DIR").map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claudia")
    static let state: URL = env("CLAUDIA_STATE_DIR").map { URL(fileURLWithPath: $0) } ?? data.appendingPathComponent("state")
    static var userQuitFlag: URL { data.appendingPathComponent("user-quit") }
    static var logFile: URL { data.appendingPathComponent("mac.log") }

    /// 程序自带的资源：.app 里是 Contents/Resources；开发时（直接跑可执行文件）用 CLAUDIA_RESOURCES 或仓库根目录
    static let resources: URL = {
        if let r = env("CLAUDIA_RESOURCES") { return URL(fileURLWithPath: r) }
        let bundled = Bundle.main.resourceURL!
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("web/index.html").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()
    static var web: URL { resources.appendingPathComponent("web") }
    static var characters: URL { resources.appendingPathComponent("characters") }
    static var plugin: URL { resources.appendingPathComponent("plugin") }
    static var version: String {
        (try? String(contentsOf: resources.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
    }

    static func env(_ name: String) -> String? {
        guard let v = ProcessInfo.processInfo.environment[name], !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return v
    }

    // ---------------- 日志 ----------------
    static func log(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: logFile) {
            defer { try? h.close() }
            if (try? h.seekToEnd()) ?? 0 > 2_000_000 { try? h.truncate(atOffset: 0) }
            h.write(line.data(using: .utf8)!)
        } else {
            try? line.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }

    // ---------------- JSON ----------------
    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    static func json(_ v: Any) -> String {
        guard JSONSerialization.isValidJSONObject([v]),
              let d = try? JSONSerialization.data(withJSONObject: [v], options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              var s = String(data: d, encoding: .utf8) else { return "null" }
        s.removeFirst(); s.removeLast()   // 去掉外面包的 [ ]
        return s
    }
    static func writeJSON(_ url: URL, _ v: Any) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let d = try JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try d.write(to: url, options: .atomic)
    }

    // ---------------- 设置（UserDefaults） ----------------
    static let defaults = UserDefaults.standard
    static func flag(_ key: String, _ fallback: Bool = true) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
    static func string(_ key: String, _ fallback: String, allowed: [String]) -> String {
        if let s = defaults.string(forKey: key), allowed.contains(s) { return s }
        return fallback
    }
    static func number(_ key: String, _ fallback: Double, _ lo: Double, _ hi: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        let n = defaults.double(forKey: key)
        return n.isFinite ? min(hi, max(lo, n)) : fallback
    }

    // ---------------- 角色清单 ----------------
    /// 网页从 claudia://app/ 读文件：网页本身在 web/，立绘在 characters/<id>/、动画在 characters/<id>/anim/
    static let scheme = "claudia"
    static let origin = "\(scheme)://app"

    static func isSprite(_ stem: String) -> Bool { !["portrait", "portrait-card", "avatar"].contains(stem) }
    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? s
    }
    static func files(_ dir: URL, ext: Set<String>) -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { ext.contains($0.pathExtension.lowercased()) }
            .sorted { Array($0.lastPathComponent.utf16).lexicographicallyPrecedes(Array($1.lastPathComponent.utf16)) }
    }

    // ---------------- 形象 ----------------
    /// 形象 = characters/ 下的一个文件夹（程序自带的 + ~/.claudia/characters/ 里你自己放的）。
    /// character.json 写了 "skinOf": "claude" 的是 claudia 的另一套衣服：没写的设置和台词沿用 claudia 的，
    /// 名字跟着 claudia 走（改名对所有衣服生效），菜单里显示 skinName。
    /// 动画精灵图和碰边翻页（animations / frames / clipLines）画的是默认那套衣服，不沿用：换装后只用自己的立绘，
    /// 衣服自己带了 anim/ 和 animations 就用自己的。
    static let baseCharacter = "claude"
    static var userCharacters: URL { data.appendingPathComponent("characters") }
    /// 角色 id → 文件夹（manifest() 里填），读图时按它找
    static var characterDirs: [String: URL] = [:]
    static let notInherited: Set<String> = ["animations", "frames", "clipLines", "name", "lines", "skinOf", "skinName"]

    static func characterFolders() -> [(id: String, dir: URL)] {
        var out: [(String, URL)] = [], seen = Set<String>()
        for root in [characters, userCharacters] {
            let dirs = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for d in dirs where seen.insert(d.lastPathComponent).inserted { out.append((d.lastPathComponent, d)) }   // 同名时自带的优先
        }
        return out
    }

    /// 扫描各个形象：character.json + 立绘（文件名去掉 -2、-3 是姿态名，idle-blink 是眨眼帧）+ anim/ 里的精灵图
    static func manifest(customName: String?) -> [String: Any] {
        var chars: [String: Any] = [:]
        var dirs: [String: URL] = [:]
        let base = readJSON(characters.appendingPathComponent("\(baseCharacter)/character.json")) ?? [:]
        let custom = customName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        for (id, dir) in characterFolders() {
            guard var info = readJSON(dir.appendingPathComponent("character.json")) else { continue }
            let family = id == baseCharacter || info["skinOf"] as? String == baseCharacter
            if id != baseCharacter && family {
                var merged = base.filter { !notInherited.contains($0.key) }
                for (k, v) in info { merged[k] = v }
                var lines = (base["lines"] as? [String: Any]) ?? [:]
                for (k, v) in (info["lines"] as? [String: Any]) ?? [:] { lines[k] = v }
                merged["lines"] = lines
                info = merged
            }
            if family { info["name"] = custom ?? (base["name"] as? String) ?? "claudia" }
            var poses: [String: [String]] = [:]
            var blink: Any = NSNull(), blinkBase: Any = NSNull()
            for f in files(dir, ext: ["webp", "png"]) {
                let stem = f.deletingPathExtension().lastPathComponent
                if !isSprite(stem) { continue }
                let url = "\(origin)/characters/\(enc(id))/\(enc(f.lastPathComponent))"
                if stem == "idle-blink" { blink = url; continue }
                if stem == "idle" { blinkBase = url }
                let pose = String(stem.split(separator: "-", omittingEmptySubsequences: false).first ?? Substring(stem))
                poses[pose, default: []].append(url)
            }
            guard poses["idle"] != nil || poses["default"] != nil else { continue }
            var sheets: [String: String] = [:]
            for f in files(dir.appendingPathComponent("anim"), ext: ["webp"]) {
                sheets[f.deletingPathExtension().lastPathComponent] = "\(origin)/characters/\(enc(id))/anim/\(enc(f.lastPathComponent))"
            }
            info["poses"] = poses; info["blink"] = blink; info["blinkBase"] = blinkBase; info["sheets"] = sheets
            chars[id] = info
            dirs[id] = dir
        }
        characterDirs = dirs
        return ["characters": chars]
    }

    /// 菜单里的形象列表：claudia 自己的几套衣服在前（默认那套第一），别的角色在后
    static func looks(_ manifest: [String: Any]) -> [(id: String, label: String)] {
        let chars = (manifest["characters"] as? [String: Any]) ?? [:]
        func info(_ id: String) -> [String: Any] { chars[id] as? [String: Any] ?? [:] }
        func family(_ id: String) -> Bool { id == baseCharacter || info(id)["skinOf"] as? String == baseCharacter }
        return chars.keys.sorted { a, b in
            if (a == baseCharacter) != (b == baseCharacter) { return a == baseCharacter }
            if family(a) != family(b) { return family(a) }
            return a < b
        }.map { id in
            let i = info(id)
            let label = id == baseCharacter ? "默认" : (i["skinName"] as? String) ?? (i["name"] as? String) ?? id
            return (id, family(id) || id == baseCharacter ? label : "\(label)（其他角色）")
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
