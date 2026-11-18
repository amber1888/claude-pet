import AppKit
import Network
import Security

// 邮件提醒：直接连邮箱（IMAP），每分钟看一次收件箱的未读，新邮件让她念出来、身边挂一个信封角标，免得漏看。
// - 只读：EXAMINE 打开收件箱、BODY.PEEK 只取发件人和主题，不会把邮件标成已读，不下载正文
// - 不依赖 Foxmail：Foxmail 关着、在别的电脑上也照样提醒；点信封打开 Foxmail（没装就打开网页邮箱）
// - 授权码存在系统钥匙串里（服务名 local.claudia-pet.mail），设置里只存邮箱地址和服务器
// - 什么都不往外发：只和你自己的邮箱服务器说话

// ---------------- 账号 ----------------
struct MailAccount: Codable, Equatable {
    var email: String
    var host: String
    var port: Int = 993
    var tls: Bool = true
    var user: String? = nil   // 登录名，空就用邮箱地址
    var web: String? = nil    // 网页邮箱（没装 Foxmail 时点信封打开）

    var id: String { email.lowercased() }
    var login: String { user?.nilIfEmpty ?? email }
}

struct MailPreset {
    let name: String, domains: [String], host: String, web: String, help: String
    static let all: [MailPreset] = [
        MailPreset(name: "QQ 邮箱 / Foxmail 邮箱", domains: ["qq.com", "vip.qq.com", "foxmail.com"], host: "imap.qq.com",
                   web: "https://mail.qq.com", help: "QQ 邮箱网页版：设置 → 账号 → 开启「IMAP/SMTP 服务」，按提示生成授权码。"),
        MailPreset(name: "腾讯企业邮", domains: [], host: "imap.exmail.qq.com",
                   web: "https://exmail.qq.com", help: "企业邮网页版：设置 → 客户端设置 → 开启 IMAP；开了安全登录的，在「微信绑定 / 安全登录」里生成客户端专用密码。"),
        MailPreset(name: "网易 163", domains: ["163.com"], host: "imap.163.com",
                   web: "https://mail.163.com", help: "163 网页版：设置 → POP3/SMTP/IMAP → 开启 IMAP 服务，新增一个授权密码。"),
        MailPreset(name: "网易 126", domains: ["126.com"], host: "imap.126.com",
                   web: "https://mail.126.com", help: "126 网页版：设置 → POP3/SMTP/IMAP → 开启 IMAP 服务，新增一个授权密码。"),
        MailPreset(name: "网易 yeah.net", domains: ["yeah.net"], host: "imap.yeah.net",
                   web: "https://mail.yeah.net", help: "网页版：设置 → POP3/SMTP/IMAP → 开启 IMAP 服务，新增一个授权密码。"),
        MailPreset(name: "Gmail", domains: ["gmail.com", "googlemail.com"], host: "imap.gmail.com",
                   web: "https://mail.google.com", help: "Google 账号 → 安全性 → 两步验证 → 应用专用密码（要先开两步验证）。"),
        MailPreset(name: "iCloud", domains: ["icloud.com", "me.com", "mac.com"], host: "imap.mail.me.com",
                   web: "https://www.icloud.com/mail", help: "appleid.apple.com → 登录与安全 → App 专用密码。"),
    ]
    static func guess(_ email: String) -> MailPreset? {
        let domain = email.split(separator: "@").last.map { $0.lowercased() } ?? ""
        return all.first { $0.domains.contains(domain) }
    }
}

enum MailKeychain {
    static let service = "local.claudia-pet.mail"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func get(_ account: String) -> String? {
        // 开发自检用：只在调试模式（CLAUDIA_DEBUG_DIR）下认这个环境变量
        if Store.env("CLAUDIA_DEBUG_DIR") != nil, let p = Store.env("CLAUDIA_MAIL_TEST_PASSWORD") { return p }
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    /// 存不进去时返回原因（比如钥匙串锁着、被拒绝）
    @discardableResult
    static func set(_ account: String, _ password: String) -> String? {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrLabel as String] = "claudia-pet 邮件提醒（\(account)）"
        let st = SecItemAdd(q as CFDictionary, nil)
        guard st != errSecSuccess else { return nil }
        let why = (SecCopyErrorMessageString(st, nil) as String?) ?? "错误 \(st)"
        Store.log("钥匙串存授权码失败（\(st)）：\(why)")
        return "\(why)（\(st)）"
    }
    static func remove(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}

// ---------------- IMAP ----------------
/// 最小的 IMAP 客户端：一问一答，够用就好（LOGIN / EXAMINE / UID SEARCH / UID FETCH / NOOP / LOGOUT）
final class ImapClient: @unchecked Sendable {
    struct Failure: LocalizedError {
        let message: String
        var auth = false
        var refused = false   // 服务器回了 NO / BAD（不是网络问题）
        var errorDescription: String? { message }
    }
    struct Response { var text: String; var literals: [Data] }

    private let conn: NWConnection
    private let queue = DispatchQueue(label: "claudia-pet.mail")
    private var buffer = Data()
    private var tag = 0
    private var deadline: DispatchWorkItem?

    init(host: String, port: Int, tls: Bool) {
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(clamping: port)),
                            using: tls ? .tls : .tcp)
    }

    /// 每一步最多等这么久，超时就断开（断开后正在等的读写会报错）
    private func arm(_ seconds: Double = 30) {
        deadline?.cancel()
        let w = DispatchWorkItem { [conn] in conn.cancel() }
        deadline = w
        queue.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    func open() async throws {
        arm()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let once = Once()   // 状态回调都在 queue 上，一个接一个来
            conn.stateUpdateHandler = { st in
                guard !once.done else { return }
                switch st {
                case .ready: once.done = true; c.resume()
                case .failed, .waiting: once.done = true; c.resume(throwing: Failure(message: "连不上服务器（网络不通，或者服务器地址不对），一分钟后自动重试"))
                case .cancelled: once.done = true; c.resume(throwing: Failure(message: "连接超时"))
                default: break
                }
            }
            conn.start(queue: queue)
        }
        let hello = try await readResponse()
        guard hello.text.hasPrefix("* OK") || hello.text.hasPrefix("* PREAUTH") else { throw Failure(message: "服务器不是 IMAP：\(hello.text.prefix(80))") }
    }

    func close() {
        deadline?.cancel()
        conn.cancel()
    }

    /// 发一条命令，收到带同样标签的 OK 为止；返回中间的 * 开头的回应
    @discardableResult
    func command(_ cmd: String) async throws -> [Response] {
        tag += 1
        let t = "c\(tag)"
        arm()
        try await send("\(t) \(cmd)\r\n")
        var out: [Response] = []
        while true {
            let r = try await readResponse()
            if r.text.hasPrefix(t + " ") {
                let rest = r.text.dropFirst(t.count + 1)
                if rest.hasPrefix("OK") { return out }
                throw Failure(message: String(rest.drop { $0 != " " }.dropFirst()).nilIfEmpty ?? String(rest), refused: true)
            }
            if r.text.hasPrefix("* ") { out.append(r) }
        }
    }

    private func send(_ s: String) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(s.utf8), completion: .contentProcessed { e in
                if let e { c.resume(throwing: Failure(message: "发送失败：\(e.localizedDescription)")) } else { c.resume() }
            })
        }
    }

    private func fill() async throws {
        let d: Data = try await withCheckedThrowingContinuation { c in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, complete, e in
                if let data, !data.isEmpty { c.resume(returning: data) }
                else if e != nil || !complete { c.resume(throwing: Failure(message: "连接断了（网络不通或服务器断开），一分钟后自动重试")) }
                else { c.resume(throwing: Failure(message: "服务器断开了连接，一分钟后自动重试")) }
            }
        }
        buffer.append(d)
        if buffer.count > 8_000_000 { throw Failure(message: "回应太大") }
    }

    private func readLine() async throws -> Data {
        while true {
            if let r = buffer.firstRange(of: Data([13, 10])) {
                let line = Data(buffer[buffer.startIndex..<r.lowerBound])
                buffer = Data(buffer[r.upperBound...])
                return line
            }
            try await fill()
        }
    }

    private func readBytes(_ n: Int) async throws -> Data {
        while buffer.count < n { try await fill() }
        let d = Data(buffer.prefix(n))
        buffer = Data(buffer.dropFirst(n))
        return d
    }

    /// 一条完整回应：行尾是 {n} 的，后面跟着 n 字节原样数据（literal），读完接着读这一行剩下的部分
    private func readResponse() async throws -> Response {
        var r = Response(text: "", literals: [])
        while true {
            let line = String(decoding: try await readLine(), as: UTF8.self)
            r.text += line
            if let m = line.range(of: #"\{(\d+)\+?\}$"#, options: .regularExpression),
               let n = Int(line[m].filter(\.isNumber)) {
                r.literals.append(try await readBytes(n))
                r.text += "\u{1}"   // literal 的位置
                continue
            }
            return r
        }
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

// ---------------- 邮件头 ----------------
struct MailHeader: Codable, Equatable {
    var uid: Int
    var from: String      // 显示名，没有就是地址
    var address: String
    var subject: String
}

enum MailParse {
    /// FROM / SUBJECT 两行头 → 解码后的发件人和主题
    static func header(uid: Int, _ raw: Data) -> MailHeader {
        let text = String(data: raw, encoding: .utf8) ?? decode(raw, charset: "gb18030") ?? String(decoding: raw, as: UTF8.self)
        var fields: [String: String] = [:]
        // 折行：下一行以空白开头的接到上一行
        let unfolded = text.replacingOccurrences(of: #"\r?\n[ \t]+"#, with: " ", options: .regularExpression)
        for line in unfolded.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let subject = words(fields["subject"] ?? "").trimmingCharacters(in: .whitespaces)
        let (name, addr) = address(words(fields["from"] ?? ""))
        return MailHeader(uid: uid, from: name.nilIfEmpty ?? addr, address: addr, subject: subject.nilIfEmpty ?? "（无主题）")
    }

    /// "张三" <zhang@x.com> → (张三, zhang@x.com)
    static func address(_ s: String) -> (String, String) {
        if let lt = s.lastIndex(of: "<"), let gt = s.lastIndex(of: ">"), lt < gt {
            let name = s[..<lt].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return (name, String(s[s.index(after: lt)..<gt]))
        }
        return ("", s.trimmingCharacters(in: .whitespaces))
    }

    /// RFC 2047：=?charset?B|Q?…?=；相邻两段编码之间的空白不算
    static func words(_ s: String) -> String {
        let pattern = #"=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?="#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = "", last = 0, lastWasWord = false
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if !(lastWasWord && between.trimmingCharacters(in: .whitespaces).isEmpty) { out += between }
            let charset = ns.substring(with: m.range(at: 1)), enc = ns.substring(with: m.range(at: 2)).uppercased()
            let body = ns.substring(with: m.range(at: 3))
            let data: Data? = enc == "B" ? base64(body) : qp(body)
            out += data.flatMap { decode($0, charset: charset) } ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
            lastWasWord = true
        }
        out += ns.substring(from: last)
        return out
    }

    static func base64(_ s: String) -> Data? {
        var t = s
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    static func qp(_ s: String) -> Data? {
        var out = Data(), chars = Array(s.utf8), i = 0
        while i < chars.count {
            let c = chars[i]
            if c == UInt8(ascii: "_") { out.append(0x20); i += 1 }
            else if c == UInt8(ascii: "="), i + 2 < chars.count, let v = UInt8(String(bytes: chars[i + 1...i + 2], encoding: .ascii) ?? "", radix: 16) {
                out.append(v); i += 3
            } else { out.append(c); i += 1 }
        }
        return out
    }

    /// 国内邮件常见 gb2312 / gbk：都按 gb18030（它们的超集）解，免得生僻字乱码
    static func decode(_ d: Data, charset: String) -> String? {
        var cs = charset.lowercased()
        if let star = cs.firstIndex(of: "*") { cs = String(cs[..<star]) }   // RFC 2231 的语言后缀
        if ["gb2312", "gbk", "x-gbk", "cp936", "euc-cn"].contains(cs) { cs = "gb18030" }
        if cs == "utf8" { cs = "utf-8" }
        let cf = CFStringConvertIANACharSetNameToEncoding(cs as CFString)
        guard cf != kCFStringEncodingInvalidId else { return String(data: d, encoding: .utf8) }
        return String(data: d, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
    }
}

// ---------------- 定时检查 ----------------
/// 每个账号一个：连着不断（每次 NOOP 一下），出错就断开、下次重连；登录失败就停下，等你改授权码
@MainActor
final class MailWatcher {
    let account: MailAccount
    private var client: ImapClient?
    private var uidValidity = ""
    private var uidNext = 0
    private var cache: [Int: MailHeader] = [:]   // 未读邮件的头，免得每次都取
    private(set) var unread: [MailHeader] = []   // 收件箱里的未读，新的在前
    private(set) var lastCheck: Date?
    private(set) var error: String?
    private(set) var authFailed = false
    private var running = false

    init(_ a: MailAccount) { account = a }

    var status: String {
        if let error { return (authFailed ? "登录失败，改授权码后再试：" : "出错：") + error }
        guard let lastCheck else { return "还没检查过" }
        return "\(unread.count) 封未读 · \(Integration.ago(lastCheck.timeIntervalSince1970))检查"
    }

    /// 上次已经告诉过你的最大 UID（按 UIDVALIDITY 分开记，邮箱重建了就重新开始）
    private var seenKey: String { "mailSeen.\(account.id).\(uidValidity)" }

    /// 检查一次；返回这次新来的邮件（第一次检查只记下位置，不把已有的未读当新邮件）
    func check() async -> [MailHeader]? {
        guard !running, !authFailed else { return nil }
        running = true
        defer { running = false }
        do {
            let c = try await connected()
            try await c.command("NOOP")
            var uids: [Int] = []
            for r in try await c.command("UID SEARCH UNSEEN") where r.text.hasPrefix("* SEARCH") {
                uids += r.text.dropFirst(8).split(separator: " ").compactMap { Int($0) }
            }
            uids.sort(by: >)
            let want = Array(uids.prefix(50))   // 只管最新的 50 封未读
            let missing = want.filter { cache[$0] == nil }
            if !missing.isEmpty {
                let set = missing.map(String.init).joined(separator: ",")
                for r in try await c.command("UID FETCH \(set) (UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])") {
                    guard let m = r.text.range(of: #"UID (\d+)"#, options: .regularExpression),
                          let uid = Int(r.text[m].dropFirst(4)), let raw = r.literals.first else { continue }
                    cache[uid] = MailParse.header(uid: uid, raw)
                }
            }
            cache = cache.filter { want.contains($0.key) }
            unread = want.compactMap { cache[$0] }
            let d = Store.defaults
            var fresh: [MailHeader] = []
            if d.object(forKey: seenKey) == nil {
                d.set(max(uidNext - 1, uids.first ?? 0), forKey: seenKey)
            } else {
                let seen = d.integer(forKey: seenKey)
                fresh = unread.filter { $0.uid > seen }
                if let top = uids.first, top > seen { d.set(top, forKey: seenKey) }
            }
            lastCheck = Date(); error = nil
            return fresh
        } catch {
            client?.close(); client = nil
            let f = error as? ImapClient.Failure
            authFailed = f?.auth ?? false
            self.error = error.localizedDescription
            Store.log("邮件 \(account.email)：\(error.localizedDescription)")
            return nil
        }
    }

    private func connected() async throws -> ImapClient {
        if let client { return client }
        guard let password = MailKeychain.get(account.id) else { throw ImapClient.Failure(message: "钥匙串里没有授权码", auth: true) }
        let c = ImapClient(host: account.host, port: account.port, tls: account.tls)
        do {
            try await c.open()
            // 网易邮箱要先报上客户端名字，否则选收件箱时说「Unsafe Login」；别家不认识就算了
            _ = try? await c.command(#"ID ("name" "claudia-pet" "version" "1.0" "vendor" "claudia-pet")"#)
            do { try await c.command("LOGIN \(ImapClient.quote(account.login)) \(ImapClient.quote(password))") }
            catch let f as ImapClient.Failure where f.refused {
                throw ImapClient.Failure(message: "\(f.message)（授权码不对，或者邮箱没开 IMAP）", auth: true)
            }
            for r in try await c.command("EXAMINE INBOX") {
                if let m = r.text.range(of: #"UIDVALIDITY (\d+)"#, options: .regularExpression) { uidValidity = String(r.text[m].dropFirst(12)) }
                if let m = r.text.range(of: #"UIDNEXT (\d+)"#, options: .regularExpression) { uidNext = Int(r.text[m].dropFirst(8)) ?? 0 }
            }
        } catch {
            c.close(); throw error
        }
        cache = [:]
        client = c
        return c
    }

    /// 菜单里「现在检查」：登录失败停下的也再试一次（可能你刚去邮箱设置里开了 IMAP）
    func retryAuth() { authFailed = false }

    func stop() {
        if let c = client { Task { _ = try? await c.command("LOGOUT"); c.close() } }
        client = nil
    }
}

/// 所有账号、设置、定时器。结果交给 Pet：onUpdate 刷新信封角标，onNew 念新邮件
@MainActor
final class MailCenter {
    static let shared = MailCenter()
    static let interval: TimeInterval = 60

    private(set) var watchers: [MailWatcher] = []
    private var timer: Timer?
    var onUpdate: (() -> Void)?
    var onNew: ((MailAccount, MailHeader, Bool) -> Void)?   // 第三个参数：是不是重要邮件

    static var accounts: [MailAccount] {
        get { (Store.defaults.data(forKey: "mailAccounts")).flatMap { try? JSONDecoder().decode([MailAccount].self, from: $0) } ?? [] }
        set { Store.defaults.set(try? JSONEncoder().encode(newValue), forKey: "mailAccounts") }
    }
    static var enabled: Bool { Store.flag("mailEnabled") }
    /// 重要邮件：发件人或主题里有这些词（逗号、空格分开）。空 = 每封都算重要
    static var vip: [String] {
        (Store.defaults.string(forKey: "mailVIP") ?? "")
            .split(whereSeparator: { ",，;；\n ".contains($0) }).map { $0.lowercased() }
    }
    static func important(_ h: MailHeader) -> Bool {
        let words = vip
        if words.isEmpty { return true }
        let hay = "\(h.from) \(h.address) \(h.subject)".lowercased()
        return words.contains { hay.contains($0) }
    }

    func reload() {
        for w in watchers { w.stop() }
        watchers = MailCenter.accounts.map(MailWatcher.init)
        timer?.invalidate(); timer = nil
        onUpdate?()
        guard MailCenter.enabled, !watchers.isEmpty else { return }
        let t = Timer(timeInterval: MailCenter.interval, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkAll() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        checkAll()
    }

    func checkAll(force: Bool = false) {
        for w in watchers {
            if force { w.retryAuth() }
            Task { @MainActor [weak self] in
                guard let fresh = await w.check() else { self?.onUpdate?(); return }
                for h in fresh.reversed() { self?.onNew?(w.account, h, MailCenter.important(h)) }   // 旧的先说
                self?.onUpdate?()
            }
        }
    }

    /// 交给网页的信封角标：{count, important, accounts: [{email, count, error}], latest: [{from, subject}]}
    var summary: [String: Any] {
        guard MailCenter.enabled else { return ["count": 0] }
        let all = watchers.flatMap(\.unread)
        return [
            "count": all.count,
            "important": all.filter(MailCenter.important).count,
            "error": watchers.contains { $0.error != nil },
            "latest": all.prefix(3).map { ["from": $0.from, "subject": $0.subject] },
        ]
    }

    /// 点信封：打开 Foxmail；没装就打开第一个有未读的邮箱的网页版
    func openMail() {
        let ws = NSWorkspace.shared
        for id in ["com.tencent.Foxmail", "com.tencent.foxmail", "com.tencent.FoxmailMac"] {
            if let url = ws.urlForApplication(withBundleIdentifier: id) { ws.openApplication(at: url, configuration: .init()); return }
        }
        for path in ["/Applications/Foxmail.app", Store.home.appendingPathComponent("Applications/Foxmail.app").path]
        where FileManager.default.fileExists(atPath: path) {
            ws.openApplication(at: URL(fileURLWithPath: path), configuration: .init()); return
        }
        let w = watchers.first { !$0.unread.isEmpty } ?? watchers.first
        if let s = w?.account.web, let url = URL(string: s) { ws.open(url) }
    }

    // ---------------- 添加 / 修改账号 ----------------
    func edit(_ old: MailAccount? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = old == nil ? "添加邮箱" : "修改邮箱"
        a.informativeText = "用 IMAP 直接看收件箱的未读（只读，不会把邮件标成已读）。密码处填邮箱的「授权码」，不是登录密码；授权码只存在系统钥匙串里。"
        let email = NSTextField(), kind = NSPopUpButton(), server = NSTextField(), code = NSSecureTextField()
        let help = NSTextField(wrappingLabelWithString: "")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor
        email.placeholderString = "you@qq.com"
        server.placeholderString = "其他邮箱才要填：imap.example.com 或 imap.example.com:993"
        code.placeholderString = old == nil ? "授权码" : "不改就留空"
        kind.addItem(withTitle: "自动（按邮箱后缀）")
        for p in MailPreset.all { kind.addItem(withTitle: p.name) }
        kind.addItem(withTitle: "其他（自己填服务器）")
        let updateHelp = {
            let i = kind.indexOfSelectedItem
            let p = i == 0 ? MailPreset.guess(email.stringValue) : (i <= MailPreset.all.count ? MailPreset.all[i - 1] : nil)
            help.stringValue = p?.help ?? "在邮箱的网页版设置里开启 IMAP，拿到授权码；服务器地址看邮箱的帮助页。"
        }
        if let old {
            email.stringValue = old.email
            if let i = MailPreset.all.firstIndex(where: { $0.host == old.host }) { kind.selectItem(at: i + 1) }
            else { kind.selectItem(at: MailPreset.all.count + 1); server.stringValue = old.port == 993 ? old.host : "\(old.host):\(old.port)" }
        }
        updateHelp()
        let target = ActionTarget(updateHelp)
        kind.target = target; kind.action = #selector(ActionTarget.fire)
        email.target = target; email.action = #selector(ActionTarget.fire)

        let grid = NSGridView(views: [
            [label("邮箱"), email], [label("类型"), kind], [label("服务器"), server], [label("授权码"), code], [NSView(), help],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.column(at: 1).width = 300
        grid.frame = NSRect(x: 0, y: 0, width: 360, height: 170)
        a.accessoryView = grid
        a.addButton(withTitle: "保存并测试"); a.addButton(withTitle: "取消")
        a.window.initialFirstResponder = old == nil ? email : code
        guard a.runModal() == .alertFirstButtonReturn else { return }
        withExtendedLifetime(target) {}

        let addr = email.stringValue.trimmingCharacters(in: .whitespaces)
        guard addr.contains("@") else { return message("邮箱地址不对：\(addr)") }
        let i = kind.indexOfSelectedItem
        var preset = i == 0 ? MailPreset.guess(addr) : (i <= MailPreset.all.count ? MailPreset.all[i - 1] : nil)
        var host = "", port = 993
        let typed = server.stringValue.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty {
            let parts = typed.split(separator: ":")
            host = String(parts[0]); port = parts.count > 1 ? Int(parts[1]) ?? 993 : 993
            preset = nil
        } else if let preset {
            host = preset.host
        } else {
            return message("认不出 \(addr) 是哪家的邮箱：在「类型」里选一下，或者填服务器地址。")
        }
        let pw = code.stringValue.trimmingCharacters(in: .whitespaces)
        if pw.isEmpty && (old == nil || old!.id != addr.lowercased()) { return message("要填授权码。") }
        let acc = MailAccount(email: addr, host: host, port: port, tls: port != 143, web: preset?.web ?? old?.web)

        var list = MailCenter.accounts.filter { $0.id != acc.id && $0.id != old?.id }
        list.append(acc)
        if !pw.isEmpty, let why = MailKeychain.set(acc.id, pw) { return message("授权码存不进钥匙串：\(why)") }
        if let old, old.id != acc.id { MailKeychain.remove(old.id) }
        MailCenter.accounts = list
        reload()
        // 测试结果：这次检查一结束就说
        let w = watchers.first { $0.account.id == acc.id }
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let w, w.lastCheck != nil || w.error != nil { break }
            }
            guard let w else { return }
            if let e = w.error { self.message("没连上 \(acc.email)：\n\(e)", title: "邮件提醒") }
            else { self.message("连上了 \(acc.email)，收件箱有 \(w.unread.count) 封未读。\n之后每分钟看一次，新邮件她会告诉你。", title: "邮件提醒") }
        }
    }

    func remove(_ acc: MailAccount) {
        MailCenter.accounts = MailCenter.accounts.filter { $0.id != acc.id }
        MailKeychain.remove(acc.id)
        for k in Store.defaults.dictionaryRepresentation().keys where k.hasPrefix("mailSeen.\(acc.id).") { Store.defaults.removeObject(forKey: k) }
        reload()
    }

    func editVIP() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "重要邮件"
        a.informativeText = "发件人（名字或地址）或主题里有这些词的算重要：她会念出来、发系统通知。逗号或空格分开，比如：\n老板@company.com, 合同, 发票, 张经理\n\n留空 = 每封新邮件都算重要。其他邮件只在信封上加数，不打扰你。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = Store.defaults.string(forKey: "mailVIP") ?? ""
        a.accessoryView = field
        a.addButton(withTitle: "保存"); a.addButton(withTitle: "取消")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Store.defaults.set(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "mailVIP")
        onUpdate?()
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }
    private func message(_ text: String, title: String = "添加邮箱") {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}

final class Once: @unchecked Sendable { var done = false }

/// NSControl 的 target-action 要一个对象
final class ActionTarget: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}
