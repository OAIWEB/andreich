import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Прозрачный слой поверх плитки: тащим файл наружу. Разрешено только КОПИРОВАНИЕ,
/// поэтому Finder не перемещает нашу копию, и на полке файл остаётся.
struct FileDragSource: NSViewRepresentable {
    let url: URL
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView(url: url, onBegin: onBegin, onEnd: onEnd) }
    func updateNSView(_ v: DragSourceView, context: Context) { v.url = url; v.onBegin = onBegin; v.onEnd = onEnd }
}

final class DragSourceView: NSView, NSDraggingSource {
    var url: URL
    var onBegin: () -> Void
    var onEnd: () -> Void
    private var down: NSPoint?

    init(url: URL, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.url = url; self.onBegin = onBegin; self.onEnd = onEnd
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        down = event.locationInWindow
        if event.clickCount == 2 { NSWorkspace.shared.open(url) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = down, hypot(event.locationInWindow.x - d.x, event.locationInWindow.y - d.y) > 4 else { return }
        down = nil
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 56, height: 56)
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let p = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - 28, y: p.y - 28, width: 56, height: 56), contents: icon)
        onBegin()
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onEnd() }
}

/// Миниатюры картинок (ImageIO, без загрузки файла целиком), с кэшем.
@MainActor
enum Thumbs {
    private static let cache = NSCache<NSString, NSImage>()
    static func image(for item: ShelfItem) -> NSImage {
        if let c = cache.object(forKey: item.id as NSString) { return c }
        var result = NSWorkspace.shared.icon(forFile: item.url.path)
        if !item.isFolder, let t = UTType(filenameExtension: item.url.pathExtension), t.conforms(to: .image),
           let src = CGImageSourceCreateWithURL(item.url as CFURL, nil) {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceCreateThumbnailWithTransform: true,
                                         kCGImageSourceThumbnailMaxPixelSize: 160]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
        cache.setObject(result, forKey: item.id as NSString)
        return result
    }
}

struct ShelfView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Полка").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text(shelf.items.isEmpty ? "бросайте файлы сюда, оригиналы остаются на месте"
                                         : "\(shelf.items.count) шт. · тащите наружу, это тоже копия")
                    .font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.55))
                Spacer()
                if !shelf.items.isEmpty {
                    Button { shelf.addViaDialog() } label: {
                        Text("Добавить…").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.black)
                            .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(tiffany))
                    }.buttonStyle(.plain).help("Выбрать файлы (или ⌘V после ⌘C в Finder)")
                    Button { shelf.clear() } label: {
                        Text("Очистить").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.14)))
                    }.buttonStyle(.plain)
                }
            }
            if let m = shelf.message {
                Text(m).font(.system(size: 11, design: .rounded)).foregroundColor(.orange)
            }
            if shelf.items.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tiffany.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 26)).foregroundColor(tiffany)
                            Text("Перетащите файлы сюда").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(tiffany)
                        })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(shelf.items) { ShelfTile(item: $0) } }
                        .padding(.vertical, 2)
                }
            }
        }
        .padding(.top, vm.geometry.notchSize.height + 6)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: Thumbs.image(for: item))
                .resizable().aspectRatio(contentMode: .fit).frame(width: 60, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.name).font(.system(size: 10, design: .rounded)).foregroundColor(.white)
                .lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
            Text(item.isFolder ? "папка" : ByteCountFormatter.string(fromByteCount: item.bytes ?? 0, countStyle: .file))
                .font(.system(size: 9, design: .rounded)).foregroundColor(.white.opacity(0.45))
        }
        .frame(width: 96, height: 110)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
        .overlay(FileDragSource(url: item.url, onBegin: { vm.isDraggingOut = true }, onEnd: { vm.isDraggingOut = false }))
        .overlay(alignment: .topTrailing) {
            Button { shelf.remove(item) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.7))
                    .background(Circle().fill(Color.black))
            }
            .buttonStyle(.plain).padding(4)
        }
    }
}
