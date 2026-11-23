// 把「用代码画的形象」（looks/drawn/rig.js：SVG 矢量画法）渲染成桌宠能用的形象文件夹：静态立绘 + 动画精灵图。
// 不用装别的：用 macOS 自带的 WebKit 把每一帧 SVG 画到 canvas 上再存图；装了 cwebp（brew install webp）就转成 WebP。
//
// 用法（平时不用直接跑，scripts/draw-looks.sh 会编译它、画好所有这类形象）：
//   swift scripts/draw-look.swift <rig.js> <形象 id> <输出文件夹>          整套：立绘、精灵图、frames.json（每张精灵图几帧）
//   swift scripts/draw-look.swift <rig.js> <形象 id> <输出.png> --preview  一张总览（所有姿态排一排），看画得怎么样
//
// rig.js 要定义全局 RIG：
//   RIG.jobs(id)  → [{kind: 'still', name, pose}, {kind: 'sheet', name, pose, frames}]
//   RIG.svg(id, pose, t, view) → SVG 字符串。t：动画进度 0～1（静态立绘是 0）；view：{w, h, s, tx, ty}，人物坐标 ×s 再平移到画布
// 人物坐标：脚底中点是原点，y 向下（人物在 y < 0 那边）。
// 尺寸和 web/index.html 的 SHEET 一致：精灵图 8 列、每格 640×360、人物高 281、脚在 321、中线 325；立绘 600×640，人物 638 高、脚踩底边。
import AppKit
import Foundation
import WebKit

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

var args = Array(CommandLine.arguments.dropFirst())
let preview = args.contains("--preview"); args.removeAll { $0 == "--preview" }
guard args.count == 3 else { fail("用法：swift scripts/draw-look.swift <rig.js> <形象 id> <输出文件夹 | 输出.png --preview>") }
let rigURL = URL(fileURLWithPath: args[0]), lookId = args[1], out = URL(fileURLWithPath: args[2])
guard let rig = try? String(contentsOf: rigURL, encoding: .utf8) else { fail("读不到 \(rigURL.path)") }

// 网页里做的事：量 idle 的外框定缩放，画每一帧，拼精灵图，回 PNG 的 base64
let harness = #"""
const SHEET = { cols: 8, w: 640, h: 360, charH: 281, feetY: 321, centerX: 325 }
const STILL = { w: 600, h: 640, charH: 638 }
async function raster(svg, w, h, ctx, dx = 0, dy = 0) {
  const url = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }))
  try {
    const img = new Image(); img.src = url; await img.decode()
    ctx.drawImage(img, dx, dy, w, h)
  } finally { URL.revokeObjectURL(url) }
}
// idle 第一帧不透明部分的外框（人物坐标）：所有姿态都按它缩放，头一样大
let box = null
async function measure(id) {
  if (box) return box
  const W = 1600, H = 1400, k = 1, view = { w: W, h: H, s: k, tx: W / 2, ty: H - 100 }
  const cv = new OffscreenCanvas(W, H), ctx = cv.getContext('2d')
  await raster(RIG.svg(id, 'idle', 0, view), W, H, ctx)
  const a = ctx.getImageData(0, 0, W, H).data
  let x0 = W, x1 = -1, y0 = H, y1 = -1
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (a[(y * W + x) * 4 + 3] > 24) {
    if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y
  }
  box = { left: (x0 - view.tx) / k, right: (x1 + 1 - view.tx) / k, top: (y0 - view.ty) / k, bottom: (y1 + 1 - view.ty) / k }
  return box
}
async function png(cv) {
  const blob = await cv.convertToBlob({ type: 'image/png' })
  const buf = new Uint8Array(await blob.arrayBuffer())
  let s = ''; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000))
  return btoa(s)
}
function viewFor(b, W, H, charH, cx, feet) {
  const s = charH / (b.bottom - b.top)
  return { w: W, h: H, s, tx: cx - (b.left + b.right) / 2 * s, ty: feet - b.bottom * s }
}
async function still(id, pose) {
  const b = await measure(id), v = viewFor(b, STILL.w, STILL.h, STILL.charH, STILL.w / 2, STILL.h - 1)
  const cv = new OffscreenCanvas(STILL.w, STILL.h)
  await raster(RIG.svg(id, pose, 0, v), STILL.w, STILL.h, cv.getContext('2d'))
  return png(cv)
}
async function sheet(id, pose, frames) {
  const b = await measure(id), v = viewFor(b, SHEET.w, SHEET.h, SHEET.charH, SHEET.centerX, SHEET.feetY)
  const rows = Math.ceil(frames / SHEET.cols)
  const cv = new OffscreenCanvas(SHEET.w * SHEET.cols, SHEET.h * rows), ctx = cv.getContext('2d')
  for (let i = 0; i < frames; i++)
    await raster(RIG.svg(id, pose, i / frames, v), SHEET.w, SHEET.h, ctx, (i % SHEET.cols) * SHEET.w, Math.floor(i / SHEET.cols) * SHEET.h)
  return png(cv)
}
// 总览：每个立绘缩小排成几行，白底，方便一眼看完
async function overview(id) {
  const poses = RIG.jobs(id).filter(j => j.kind === 'still').map(j => j.pose)
  const b = await measure(id), cw = 300, ch = 330, cols = 6, rows = Math.ceil(poses.length / cols)
  const cv = new OffscreenCanvas(cw * cols, ch * rows), ctx = cv.getContext('2d')
  ctx.fillStyle = '#f3f0ee'; ctx.fillRect(0, 0, cv.width, cv.height)
  for (let i = 0; i < poses.length; i++) {
    const v = viewFor(b, cw, ch, 300, cw / 2, ch - 22)
    await raster(RIG.svg(id, poses[i], 0, v), cw, ch, ctx, (i % cols) * cw, Math.floor(i / cols) * ch)
    ctx.fillStyle = '#555'; ctx.font = '16px Menlo'; ctx.fillText(poses[i], (i % cols) * cw + 8, Math.floor(i / cols) * ch + ch - 4)
  }
  return png(cv)
}
"""#

final class Runner: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let rig: String, lookId: String, out: URL, preview: Bool
    init(rig: String, lookId: String, out: URL, preview: Bool) { self.rig = rig; self.lookId = lookId; self.out = out; self.preview = preview }
    func start() {
        web.navigationDelegate = self
        web.loadHTMLString("<!doctype html><meta charset=utf-8><script>\(rig)\n\(harness)</script>", baseURL: nil)
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { Task { @MainActor in await self.run(); exit(0) } }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { fail("网页加载失败：\(e)") }

    @MainActor func call(_ js: String) async -> String {
        do {
            guard let s = try await web.callAsyncJavaScript(js, arguments: [:], contentWorld: .page) as? String else { fail("没拿到结果：\(js)") }
            return s
        } catch { fail("出错：\(js)\n\(error)") }
    }
    func save(_ b64: String, _ url: URL, quality: Int) {
        guard let data = Data(base64Encoded: b64) else { fail("图片数据坏了：\(url.path)") }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pngURL = url.deletingPathExtension().appendingPathExtension("png")
        do { try data.write(to: pngURL) } catch { fail("写不了 \(pngURL.path)：\(error)") }
        guard url.pathExtension == "webp", let cwebp = which("cwebp") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cwebp)
        p.arguments = ["-quiet", "-q", String(quality), "-alpha_q", "95", "-m", "5", pngURL.path, "-o", url.path]
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus == 0 { try? FileManager.default.removeItem(at: pngURL) }
    }
    func which(_ tool: String) -> String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func js(_ s: String) -> String { String(data: try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed]), encoding: .utf8)!.dropFirst().dropLast().description }

    @MainActor func run() async {
        let id = js(lookId)
        if preview {
            save(await call("return await overview(\(id))"), out, quality: 0)
            print("总览：\(out.path)"); return
        }
        let jobsJSON = await call("return JSON.stringify(RIG.jobs(\(id)))")
        guard let jobs = try? JSONSerialization.jsonObject(with: Data(jobsJSON.utf8)) as? [[String: Any]] else { fail("RIG.jobs 不对") }
        let ext = which("cwebp") == nil ? "png" : "webp"
        var frames: [String: Int] = [:]
        for j in jobs {
            guard let kind = j["kind"] as? String, let name = j["name"] as? String, let pose = j["pose"] as? String else { continue }
            if kind == "still" {
                save(await call("return await still(\(id), \(js(pose)))"), out.appendingPathComponent("\(name).\(ext)"), quality: 92)
            } else if kind == "sheet", let n = j["frames"] as? Int {
                frames[name] = n
                guard ext == "webp" else { continue }   // 桌宠只认 WebP 的精灵图：没有 cwebp 就不出动画，只用静态立绘
                save(await call("return await sheet(\(id), \(js(pose)), \(n))"), out.appendingPathComponent("anim/\(name).webp"), quality: 86)
            }
            print("  \(kind == "still" ? "立绘" : "精灵图") \(name)")
        }
        let f = try! JSONSerialization.data(withJSONObject: frames, options: [.sortedKeys])
        try? f.write(to: out.appendingPathComponent("frames.json"))
        print("完成：\(out.path)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let runner = Runner(rig: rig, lookId: lookId, out: out, preview: preview)
runner.start()
app.run()
