// Видео → зацикленная последовательность PNG с прозрачным фоном.
// 1) ffmpeg режет кадры, 2) Vision вырезает персонажа, 3) общая рамка для всех кадров (без дрожания),
// 4) ищем кадр, наиболее похожий на первый, и обрезаем там цикл.
// Запуск: swiftc -O -o v2s scripts/video2sprite.swift && ./v2s ролик.mp4 папка [fps=15] [высота=360]
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }
let a = CommandLine.arguments
guard a.count >= 3 else { die("usage: v2s <video> <outdir> [fps] [height]") }
let video = a[1], outDir = URL(fileURLWithPath: a[2])
let fps = a.count > 3 ? Int(a[3]) ?? 15 : 15
let targetH = a.count > 4 ? Int(a[4]) ?? 360 : 360
let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("v2s-\(UUID().uuidString)")
try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
try? fm.removeItem(at: outDir); try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

// 1. кадры
let p = Process()
p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
p.arguments = ["-loglevel", "error", "-i", video, "-vf", "fps=\(fps)", tmp.appendingPathComponent("f_%04d.png").path]
try p.run(); p.waitUntilExit()
let frames = (try fm.contentsOfDirectory(atPath: tmp.path)).filter { $0.hasPrefix("f_") }.sorted()
guard !frames.isEmpty else { die("кадров нет") }
print("кадров из видео:", frames.count)

// 2. вырезаем персонажа
let ci = CIContext()
func load(_ url: URL) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}
struct Cut { var img: CGImage; var box: CGRect }
func alphaBox(_ img: CGImage) -> CGRect {
    let w = img.width, h = img.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    let c = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var x0 = w, x1 = 0, y0 = h, y1 = 0
    for y in 0..<h { for x in 0..<w where d[(y * w + x) * 4 + 3] > 20 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return x1 > x0 ? CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1) : .zero
}
var cuts: [Cut] = []
for f in frames {
    guard let img = load(tmp.appendingPathComponent(f)) else { continue }
    let h = VNImageRequestHandler(cgImage: img, options: [:])
    let r = VNGenerateForegroundInstanceMaskRequest()
    try? h.perform([r])
    guard let obs = r.results?.first,
          let buf = try? obs.generateMaskedImage(ofInstances: obs.allInstances, from: h, croppedToInstancesExtent: false) else { continue }
    let im = CIImage(cvPixelBuffer: buf)
    guard let out = ci.createCGImage(im, from: im.extent) else { continue }
    cuts.append(Cut(img: out, box: alphaBox(out)))
}
guard !cuts.isEmpty else { die("персонаж не найден") }

// 3. общая рамка
var u = cuts[0].box
for c in cuts { u = u.union(c.box) }
u = u.insetBy(dx: -6, dy: -6).intersection(CGRect(x: 0, y: 0, width: cuts[0].img.width, height: cuts[0].img.height))
let scale = Double(targetH) / Double(u.height)
let outW = Int((Double(u.width) * scale).rounded()), outH = targetH

func render(_ c: Cut) -> CGImage {
    // CGImage.cropping работает в координатах изображения (начало сверху), alphaBox — снизу: переводим
    let flipped = CGRect(x: u.minX, y: CGFloat(c.img.height) - u.maxY, width: u.width, height: u.height)
    let cropped = c.img.cropping(to: flipped)!
    let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    return ctx.makeImage()!
}
let rendered = cuts.map(render)

// 4. точка цикла: самый похожий на первый кадр (не раньше 0,6 с)
func thumb(_ img: CGImage) -> [Double] {
    let n = 32
    var d = [UInt8](repeating: 0, count: n * n * 4)
    let c = CGContext(data: &d, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
    return stride(from: 0, to: d.count, by: 4).map { Double(d[$0]) + Double(d[$0 + 1]) + Double(d[$0 + 2]) + Double(d[$0 + 3]) }
}
let t0 = thumb(rendered[0])
var best = rendered.count, bestScore = Double.greatestFiniteMagnitude
let minLen = max(4, Int(Double(fps) * 0.6))
if rendered.count > minLen + 1 {
    for i in minLen..<rendered.count {
        let ti = thumb(rendered[i])
        let s = zip(t0, ti).reduce(0) { $0 + abs($1.0 - $1.1) }
        if s < bestScore { bestScore = s; best = i }
    }
}
let loop = Array(rendered[0..<best])
for (i, img) in loop.enumerated() {
    let url = outDir.appendingPathComponent(String(format: "%03d.png", i))
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}
try? fm.removeItem(at: tmp)
print("цикл: \(loop.count) кадров (\(String(format: "%.2f", Double(loop.count) / Double(fps))) с) из \(rendered.count), размер \(outW)×\(outH)")
