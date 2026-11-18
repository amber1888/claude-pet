// 把生图工具画出来的立绘整理成桌宠能直接用的形象文件夹。不用装任何东西（macOS 自带的 swift 就能跑）。
//
// 用法：
//   swift scripts/prepare-look.swift <原图文件夹> <形象 id> [--name 菜单里的名字] [--out 输出文件夹] [--sit 姿态,姿态] [--white-bg]
// 例：
//   swift scripts/prepare-look.swift ~/Downloads/maid maid --name 女仆
//   → 输出到 ~/.claudia/characters/maid/，然后在桌宠菜单「外观 → 形象 → 重新扫描形象」
//
// 原图：透明背景的 PNG（jpg / webp 也能读），文件名是姿态名：idle.png、thinking.png、happy-2.png……（见 docs/looks/README.md）
// 每张做的事：
//   1. 几乎不透明的像素（alpha ≥ 250）补成全不透明；离主体很远的小碎块（杂点、飘在空中的特效）去掉。
//   2. 裁掉空白，缩放后放到 640 高的透明画布上，脚踩在底边、左右居中（和自带立绘一样的规格）。
//      站着的姿态：人物缩到 638 高。坐着、躺着的（sleeping、tired 等，见 SITTING，可用 --sit 追加）不放大到整高，
//      而是用和 idle 一样的缩放倍数，这样头的大小和站着时一致（前提是生图时人物画得差不多大）。
//   3. idle-blink（眨眼帧）完全照 idle 的裁剪和缩放来摆，两张才能严丝合缝地叠在一起；所以 idle-blink 要和 idle 同样尺寸，
//      最好是拿 idle 改的（只把眼睛改成闭眼）。
//   4. 存成 PNG；装了 cwebp（brew install webp）就存成 WebP（质量 92），体积小很多。
//   --white-bg：生图工具没给真透明、给了白底时，把和四边连着的近白色当背景抠掉（发白的衣服边可能被吃掉一点，看一眼再用）。
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let HEIGHT = 640, PERSON = 638, MAX_WIDTH = 880
var SITTING: Set<String> = ["sleeping", "tired", "sulk", "fallen", "faceplant", "dizzy"]
let CORE = ["idle", "idle-blink", "listening", "thinking", "reading", "writing", "running", "happy", "oops", "asking"]
let NICE = ["searching", "delegating", "proud", "surprised", "sleeping", "pat", "tired", "sorry", "compact", "busy_left", "busy_right"]
let KNOWN: Set<String> = Set(CORE + NICE + ["hum", "stretch", "yawn", "annoyed", "puffed", "redhot", "sulk", "coaxed", "forgiven", "dizzy",
    "clawd", "swamped_left", "swamped_right", "bye", "update", "pout", "bonk", "stagger", "fallen", "faceplant", "default",
    "greet_morning", "greet_noon", "greet_afternoon", "greet_evening", "greet_night", "portrait", "portrait-card", "avatar"])

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

// ---------------- 参数 ----------------
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}
let displayName = option("--name")
let outOption = option("--out")
if let s = option("--sit") { for p in s.split(separator: ",") { SITTING.insert(String(p).trimmingCharacters(in: .whitespaces)) } }
let whiteBg = flag("--white-bg")
guard args.count == 2 else {
    fail("用法：swift scripts/prepare-look.swift <原图文件夹> <形象 id> [--name 名字] [--out 输出文件夹] [--sit 姿态,姿态] [--white-bg]")
}
let inDir = URL(fileURLWithPath: (args[0] as NSString).expandingTildeInPath)
let id = args[1]
guard id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil, id != "claude" else {
    fail("形象 id 只能用英文字母、数字、- 和 _，也不能叫 claude（那是默认形象）")
}
let home = FileManager.default.homeDirectoryForCurrentUser
let outDir = outOption.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    ?? home.appendingPathComponent(".claudia/characters/\(id)")
let cwebp = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"].first { FileManager.default.isExecutableFile(atPath: $0) }

// ---------------- 像素 ----------------
struct Bitmap {
    var w: Int, h: Int, px: [UInt8]   // RGBA，预乘 alpha
    func a(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }
}

func load(_ url: URL) -> Bitmap? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ok = px.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? Bitmap(w: w, h: h, px: px) : nil
}

func cgImage(_ b: Bitmap) -> CGImage {
    var px = b.px
    let ctx = px.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: b.w, height: b.h, bitsPerComponent: 8, bytesPerRow: b.w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    return ctx.makeImage()!
}

/// 和四边连着的近白色当背景抠掉
func removeWhite(_ b: inout Bitmap) {
    func white(_ i: Int) -> Bool { b.px[i * 4 + 3] > 200 && b.px[i * 4] > 235 && b.px[i * 4 + 1] > 235 && b.px[i * 4 + 2] > 235 }
    var seen = [Bool](repeating: false, count: b.w * b.h), stack: [Int] = []
    for x in 0..<b.w { stack.append(x); stack.append((b.h - 1) * b.w + x) }
    for y in 0..<b.h { stack.append(y * b.w); stack.append(y * b.w + b.w - 1) }
    while let i = stack.popLast() {
        if seen[i] || !white(i) { continue }
        seen[i] = true
        for k in 0..<4 { b.px[i * 4 + k] = 0 }
        let x = i % b.w, y = i / b.w
        if x > 0 { stack.append(i - 1) }; if x < b.w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - b.w) }; if y < b.h - 1 { stack.append(i + b.w) }
    }
}

/// alpha 补满；去掉小碎块（连通块面积不到最大块的 2%）。返回去掉了几块
func clean(_ b: inout Bitmap) -> Int {
    let n = b.w * b.h
    for i in 0..<n where b.px[i * 4 + 3] >= 250 {
        let a = Double(b.px[i * 4 + 3])
        for k in 0..<3 { b.px[i * 4 + k] = UInt8(min(255, Double(b.px[i * 4 + k]) * 255 / a)) }
        b.px[i * 4 + 3] = 255
    }
    var label = [Int32](repeating: 0, count: n), sizes: [Int] = [0], stack: [Int] = []
    for start in 0..<n where label[start] == 0 && b.px[start * 4 + 3] >= 16 {
        let lab = Int32(sizes.count); var size = 0
        stack.append(start); label[start] = lab
        while let i = stack.popLast() {
            size += 1
            let x = i % b.w, y = i / b.w
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < b.w, ny < b.h else { continue }
                let j = ny * b.w + nx
                if label[j] == 0 && b.px[j * 4 + 3] >= 16 { label[j] = lab; stack.append(j) }
            }
        }
        sizes.append(size)
    }
    guard let biggest = sizes.max(), biggest > 0 else { return 0 }
    let small = Set(sizes.indices.filter { $0 > 0 && sizes[$0] < biggest / 50 }.map { Int32($0) })
    if small.isEmpty { return 0 }
    for i in 0..<n where small.contains(label[i]) { for k in 0..<4 { b.px[i * 4 + k] = 0 } }
    // 淡淡的半透明边（alpha < 16）也清掉，免得包围盒被撑大
    for i in 0..<n where b.px[i * 4 + 3] < 16 { for k in 0..<4 { b.px[i * 4 + k] = 0 } }
    return small.count
}

func bbox(_ b: Bitmap) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
    var x0 = b.w, y0 = b.h, x1 = -1, y1 = -1
    for y in 0..<b.h { for x in 0..<b.w where b.a(x, y) >= 64 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return x1 < 0 ? nil : (x0, y0, x1, y1)
}

/// 裁出 box、按 scale 缩放，放到 640 高的画布上：底边贴地、水平居中
struct Placement { var box: (x0: Int, y0: Int, x1: Int, y1: Int); var scale: Double }
func place(_ b: Bitmap, _ p: Placement) -> (CGImage, Int) {
    let bw = Double(p.box.x1 - p.box.x0 + 1), bh = Double(p.box.y1 - p.box.y0 + 1)
    let dw = bw * p.scale, dh = bh * p.scale
    let width = min(MAX_WIDTH, max(Int(ceil(dw)) + 4, 200))
    let ctx = CGContext(data: nil, width: width, height: HEIGHT, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let crop = cgImage(b).cropping(to: CGRect(x: p.box.x0, y: p.box.y0, width: Int(bw), height: Int(bh)))!
    // CG 坐标原点在左下：底边留 1 像素，和自带立绘一样
    ctx.draw(crop, in: CGRect(x: (Double(width) - dw) / 2, y: 1, width: dw, height: dh))
    return (ctx.makeImage()!, width)
}

func save(_ img: CGImage, _ name: String) -> URL {
    let png = outDir.appendingPathComponent(name + ".png")
    let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fail("写不了 \(png.path)") }
    guard let cwebp else { return png }
    let webp = outDir.appendingPathComponent(name + ".webp")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cwebp)
    p.arguments = ["-quiet", "-q", "92", "-alpha_q", "100", "-exact", png.path, "-o", webp.path]
    try? p.run(); p.waitUntilExit()
    if p.terminationStatus == 0 { try? FileManager.default.removeItem(at: png); return webp }
    return png
}

// ---------------- 开始 ----------------
let fm = FileManager.default
let inputs = ((try? fm.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)) ?? [])
    .filter { ["png", "webp", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !inputs.isEmpty else { fail("\(inDir.path) 里没有图片") }
guard inputs.contains(where: { $0.deletingPathExtension().lastPathComponent == "idle" }) else {
    fail("缺 idle.png（待机图）：桌宠靠它认出这是一个形象，坐着躺着的缩放也按它算")
}
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
print("输出到 \(outDir.path)\(cwebp == nil ? "（没装 cwebp，存 PNG；brew install webp 后重跑可存成更小的 WebP）" : "")")

// 先做 idle：它的缩放倍数是坐姿的基准，裁剪框给眨眼帧用
let ordered = inputs.sorted { a, b in
    let pa = a.deletingPathExtension().lastPathComponent, pb = b.deletingPathExtension().lastPathComponent
    return (pa == "idle" ? 0 : pa == "idle-blink" ? 2 : 1, pa) < (pb == "idle" ? 0 : pb == "idle-blink" ? 2 : 1, pb)
}
var idlePlacement: Placement?, idleSize: (Int, Int)?
var done: [String] = []
for url in ordered {
    let name = url.deletingPathExtension().lastPathComponent
    let pose = String(name.split(separator: "-").first ?? Substring(name))
    if !KNOWN.contains(pose) && name != "idle-blink" {
        print("  跳过 \(url.lastPathComponent)：不认识的姿态名（拼写对吗？见 docs/looks/README.md 的姿态表）")
        continue
    }
    guard var b = load(url) else { print("  跳过 \(url.lastPathComponent)：读不了"); continue }
    let opaqueCorners = [b.a(0, 0), b.a(b.w - 1, 0), b.a(0, b.h - 1), b.a(b.w - 1, b.h - 1)].filter { $0 > 200 }.count
    if whiteBg { removeWhite(&b) } else if opaqueCorners >= 3 {
        print("  ⚠️ \(url.lastPathComponent)：四个角不透明，背景可能没去掉（重新生成时打开透明背景，或加 --white-bg 抠白底）")
    }
    let removed = clean(&b)
    var p: Placement
    if name == "idle-blink", let ip = idlePlacement, let (iw, ih) = idleSize {
        if (b.w, b.h) != (iw, ih) { print("  ⚠️ idle-blink 和 idle 尺寸不同（\(b.w)x\(b.h) / \(iw)x\(ih)），眨眼时会错位：最好拿 idle 改图得到它") }
        p = ip
    } else {
        guard let box = bbox(b) else { print("  跳过 \(url.lastPathComponent)：整张是空的"); continue }
        let h = Double(box.y1 - box.y0 + 1)
        // CGContext 的行是从上往下存的，bbox 的 y 也是从上往下；cropping 用的也是从上往下的坐标，不用翻
        if SITTING.contains(pose), let ip = idlePlacement { p = Placement(box: box, scale: ip.scale) }
        else { p = Placement(box: box, scale: Double(PERSON) / h) }
        if Double(box.x1 - box.x0 + 1) * p.scale > Double(MAX_WIDTH - 4) {   // 太宽：整张缩小到放得下
            p.scale = Double(MAX_WIDTH - 4) / Double(box.x1 - box.x0 + 1)
        }
        if p.scale * h > Double(HEIGHT - 1) { p.scale = Double(HEIGHT - 1) / h }
        if name == "idle" { idlePlacement = p; idleSize = (b.w, b.h) }
    }
    let (img, width) = place(b, p)
    let saved = save(img, name)
    done.append(name)
    print("  ✓ \(saved.lastPathComponent)  \(width)x\(HEIGHT)\(removed > 0 ? "  去掉碎块 \(removed) 个" : "")\(SITTING.contains(pose) && name != "idle" ? "  （坐 / 躺：按 idle 的倍数缩放）" : "")")
}

// character.json：没有就写一份最简的（沿用 claudia 的台词和设置）；有就不动
let json = outDir.appendingPathComponent("character.json")
if !fm.fileExists(atPath: json.path) {
    let body: [String: Any] = ["skinOf": "claude", "skinName": displayName ?? id]
    let d = try! JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
    try! d.write(to: json)
    print("  ✓ character.json（skinOf: claude，菜单名「\(displayName ?? id)」；想换台词照 docs/looks/README.md 加 lines）")
} else if let name = displayName {
    print("  character.json 已存在，没改（菜单名想改成「\(name)」就手动改 skinName）")
}

let poses = Set(done.map { String($0.split(separator: "-").first ?? Substring($0)) })
let missingCore = CORE.filter { $0 == "idle-blink" ? !done.contains("idle-blink") : !poses.contains($0) }
let missingNice = NICE.filter { !poses.contains($0) }
print("")
print(missingCore.isEmpty ? "必画的都齐了。" : "还缺必画的：\(missingCore.joined(separator: "、"))（缺的会用相近的姿态或 idle 顶上）")
if !missingNice.isEmpty { print("建议补的：\(missingNice.joined(separator: "、"))") }
print("下一步：桌宠菜单「外观 → 形象 → 重新扫描形象」，再选「\(displayName ?? id)」。")
