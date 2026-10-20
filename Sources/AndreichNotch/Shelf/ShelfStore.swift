import AppKit
import SwiftUI

struct ShelfItem: Identifiable, Equatable {
    let id: String        // имя папки-контейнера
    let url: URL          // наша копия файла
    let name: String
    let bytes: Int64?
    let isFolder: Bool
    let added: Date
}

/// Полка: файлы, брошенные в чёлку, копируются в ~/Library/Application Support/AndreichNotch/shelf.
/// Оригиналы не трогаются, и наружу тоже уходит копия.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var message: String?

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AndreichNotch/shelf")
    }

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.root, withIntermediateDirectories: true)
        var found: [ShelfItem] = []
        for dir in (try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: [.creationDateKey])) ?? [] {
            guard let file = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.first else { continue }
            let rv = try? file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let added = (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            found.append(ShelfItem(id: dir.lastPathComponent, url: file, name: file.lastPathComponent,
                                   bytes: rv?.fileSize.map(Int64.init), isFolder: rv?.isDirectory ?? false, added: added))
        }
        items = found.sorted { $0.added > $1.added }
    }

    /// Копирует на полку (в фоне, чтобы большие файлы не вешали чёлку).
    func add(_ urls: [URL]) {
        let root = Self.root
        Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            var failed: [String] = []
            for u in urls {
                let dir = root.appendingPathComponent(UUID().uuidString)
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try fm.copyItem(at: u, to: dir.appendingPathComponent(u.lastPathComponent))
                } catch {
                    try? fm.removeItem(at: dir)
                    failed.append(u.lastPathComponent)
                }
            }
            await MainActor.run {
                self?.reload()
                self?.message = failed.isEmpty ? nil : "Не удалось скопировать: " + failed.joined(separator: ", ")
            }
        }
    }

    func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(item.id))
        reload()
    }

    /// Вставка из буфера: ⌘C на файле в Finder → ⌘V в полку. Обход шторки Dropover.
    func pasteFromPasteboard() {
        let urls = (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { add(urls) }
    }

    /// Диалог выбора файлов — когда перетаскивание перехватывают чужие шторки.
    func addViaDialog() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        NSApp.activate(ignoringOtherApps: true)
        p.begin { [weak self] r in
            guard r == .OK else { return }
            Task { @MainActor in self?.add(p.urls) }
        }
    }

    func clear() {
        for item in items { try? FileManager.default.removeItem(at: Self.root.appendingPathComponent(item.id)) }
        reload()
    }
}
