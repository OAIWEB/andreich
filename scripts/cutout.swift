// Вырезает персонажей с листа в прозрачные PNG средствами macOS Vision (без внешних моделей).
// Запуск: swiftc -o cutout scripts/cutout.swift && ./cutout лист.webp папка_вывода
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

let args = CommandLine.arguments
guard args.count >= 3 else { die("usage: cutout <image> <outdir>") }
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { die("не открылся файл") }
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let obs = request.results?.first else { die("объекты не найдены") }
let ctx = CIContext()

struct Item { var image: CGImage; var minX: Int }
var items: [Item] = []
for idx in obs.allInstances {
    let buf = try obs.generateMaskedImage(ofInstances: IndexSet(integer: idx), from: handler, croppedToInstancesExtent: false)
    let ci = CIImage(cvPixelBuffer: buf)
    guard let full = ctx.createCGImage(ci, from: ci.extent) else { continue }
    // габариты по альфа-каналу
    let w = full.width, h = full.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    let c = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, maxX = 0, minY = h, maxY = 0
    for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    if maxX <= minX || maxY <= minY || (maxX - minX) * (maxY - minY) < 4000 { continue }   // мелкий мусор
    let pad = 4
    let rect = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                      width: min(w, maxX + pad) - max(0, minX - pad), height: min(h, maxY + pad) - max(0, minY - pad))
    guard let cropped = full.cropping(to: rect) else { continue }
    items.append(Item(image: cropped, minX: minX))
}
items.sort { $0.minX < $1.minX }
print("найдено персонажей: \(items.count)")
for (i, it) in items.enumerated() {
    let url = outDir.appendingPathComponent("raw-\(i + 1).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, it.image, nil)
    CGImageDestinationFinalize(dest)
    print(url.lastPathComponent, it.image.width, "x", it.image.height)
}
