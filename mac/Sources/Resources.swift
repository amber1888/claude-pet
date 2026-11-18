import Foundation
import WebKit

/// claudia://app/… → 程序自带的文件。只认两种形状：
///   /<网页文件>                          → web/ 里的 html / js / css
///   /characters/<角色>/[anim/]<图>       → 立绘、动画精灵图（只给 .webp / .png；角色文件夹可能在程序里，也可能在 ~/.claudia/characters）
/// 别的（目录跳转、character.json、设置）一律不给。
final class ResourceHandler: NSObject, WKURLSchemeHandler {
    private var stopped = Set<ObjectIdentifier>()
    private let io = DispatchQueue(label: "claudia.resources", qos: .userInitiated, attributes: .concurrent)

    static func resolve(_ path: String) -> (URL, String)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map { String($0).removingPercentEncoding ?? "" }
        func safe(_ s: String) -> Bool { !s.isEmpty && s != "." && s != ".." && !s.contains("/") && !s.contains("\0") }
        guard parts.first == "" else { return nil }
        let segs = Array(parts.dropFirst())
        if segs.count == 1 {
            let name = segs[0]
            guard safe(name) else { return nil }
            let mime: String
            switch (name as NSString).pathExtension.lowercased() {
            case "html": mime = "text/html; charset=utf-8"
            case "js": mime = "text/javascript; charset=utf-8"
            case "css": mime = "text/css; charset=utf-8"
            default: return nil
            }
            return (Store.web.appendingPathComponent(name), mime)
        }
        let anim = segs.count == 4 && segs[2] == "anim"
        guard segs.first == "characters", segs.count == 3 || anim, segs.dropFirst().allSatisfy(safe) else { return nil }
        let name = segs.last!
        let ext = (name as NSString).pathExtension.lowercased()
        guard ext == "webp" || ext == "png" else { return nil }
        guard var url = Store.characterDirs[segs[1]] else { return nil }   // 只给清单里有的形象
        if anim { url.appendPathComponent("anim") }
        url.appendPathComponent(name)
        return (url, ext == "webp" ? "image/webp" : "image/png")
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        guard let req = task.request.url, req.host == "app", let (file, mime) = Self.resolve(req.path.isEmpty ? "/" : req.path) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        io.async { [weak self] in
            let data = try? Data(contentsOf: file)
            DispatchQueue.main.async {
                guard let self, !self.stopped.contains(key) else { self?.stopped.remove(key); return }
                guard let data else {
                    Store.log("读文件失败: \(file.path)")
                    task.didFailWithError(URLError(.fileDoesNotExist)); return
                }
                let resp = HTTPURLResponse(url: req, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                    "Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-store",
                ])!
                task.didReceive(resp)
                task.didReceive(data)
                task.didFinish()
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stopped.insert(ObjectIdentifier(task))
    }
}
