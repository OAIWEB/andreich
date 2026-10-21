import AppKit
import Combine
import SwiftUI

/// Окно поверх выреза: на всех рабочих столах, поверх полноэкранных приложений.
/// Приём (уровень окна, collectionBehavior) известен по открытому Atoll (MIT).
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum NotchTab { case assistant, journal, shelf }

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var tab: NotchTab = .assistant
    /// Пока тащим файл из полки наружу, панель не закрываем.
    var isDraggingOut = false
    /// Над чёлкой тащат файл снаружи: панель держим открытой и подсвечиваем рамку.
    @Published var isDragOver = false
    /// Содержимое раскрытой панели живёт в дереве SwiftUI только пока оно нужно (иначе анимации крутятся впустую).
    @Published var contentMounted = false
    private var unmountTask: Task<Void, Never>?
    /// Контроллер меняет размер окна: большое на время раскрытия, маленькое в покое.
    var requestFrame: ((Bool) -> Void)?
    @Published var geometry: NotchGeometry

    static let wing: CGFloat = 46
    static let flare: CGFloat = 8
    static let openSize = CGSize(width: 680, height: 326)

    /// Отладка: ANDREICH_PIN=1 не даёт панели закрываться.
    private static let pinned = ProcessInfo.processInfo.environment["ANDREICH_PIN"] != nil
    private var hoverT: TimeInterval = 0
    private var leaveT: TimeInterval = 0

    init(geometry: NotchGeometry) { self.geometry = geometry }

    var closedBody: CGSize { CGSize(width: geometry.notchSize.width + 2 * Self.wing, height: geometry.notchSize.height) }

    var closedRect: CGRect {
        let w = closedBody.width + 2 * Self.flare
        return CGRect(x: geometry.screenFrame.midX - w / 2, y: geometry.screenFrame.maxY - closedBody.height,
                      width: w, height: closedBody.height)
    }
    var openRect: CGRect {
        let w = Self.openSize.width + 2 * Self.flare
        return CGRect(x: geometry.screenFrame.midX - w / 2, y: geometry.screenFrame.maxY - Self.openSize.height,
                      width: w, height: Self.openSize.height)
    }

    func open() {
        guard !isOpen else { return }
        unmountTask?.cancel()
        requestFrame?(true)
        contentMounted = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { isOpen = true }
    }
    func close() {
        guard isOpen else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { isOpen = false }
        unmountTask?.cancel()
        unmountTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.contentMounted = false
            self?.requestFrame?(false)
        }
    }
    func toggle() { isOpen ? close() : open() }

    /// Вызывается каждый тик: открываем после 0,2 с наведения, закрываем через 0,4 с после ухода курсора.
    func pollMouse(_ m: CGPoint, dt: TimeInterval) {
        if !isOpen {
            if closedRect.insetBy(dx: -2, dy: -4).contains(m) { hoverT += dt; if hoverT >= 0.2 { open() } }
            else { hoverT = 0 }
        } else {
            if Self.pinned || isDraggingOut || isDragOver { return }
            if openRect.insetBy(dx: -12, dy: -12).contains(m) { leaveT = 0 }
            else { leaveT += dt; if leaveT >= 0.4 { close(); hoverT = 0 } }
        }
    }
}

@MainActor
final class NotchController {
    static var dbgLast = Date.distantPast
    let panel: NotchPanel
    let vm: NotchViewModel

    init(geometry: NotchGeometry, brain: PetBrain, monitor: ClaudeMonitor, voice: VoiceListener, shelf: ShelfStore, limits: UsageMonitor, analyst: ProtocolAnalyst) {
        vm = NotchViewModel(geometry: geometry)
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        let host = FirstMouseHostingView(
            rootView: NotchView().environmentObject(vm).environmentObject(brain).environmentObject(monitor).environmentObject(voice).environmentObject(shelf).environmentObject(limits).environmentObject(analyst))
        panel.contentView = host
        host.armForFileDrops()
        let vmRef = vm
        host.onDragEnter = { [weak self] in
            vmRef.isDragOver = true
            vmRef.tab = .shelf
            vmRef.open()
            self?.panel.ignoresMouseEvents = false
        }
        host.onDragExit = { vmRef.isDragOver = false }
        host.onDropURLs = { urls in
            vmRef.isDragOver = false
            guard !urls.isEmpty else { return false }
            shelf.add(urls)
            vmRef.tab = .shelf
            vmRef.open()
            return true
        }
        applyFrame()
        panel.orderFrontRegardless()
        vm.requestFrame = { [weak self] open in self?.applyFrame(open: open) }
        // ⌘V в раскрытой чёлке кладёт файлы из буфера в полку (обход чужих шторок перетаскивания)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak vm] e in
            guard let vm, vm.isOpen, e.modifierFlags.contains(.command),
                  e.charactersIgnoringModifiers?.lowercased() == "v" else { return e }
            vm.tab = .shelf
            shelf.pasteFromPasteboard()
            return nil
        }
    }

    /// В покое окно ровно с чёлку (дёшево для отрисовки), на время раскрытия растёт до полного размера.
    func applyFrame(open: Bool = false) {
        let g = vm.geometry
        let size: CGSize = open
            ? CGSize(width: NotchViewModel.openSize.width + 2 * (NotchViewModel.flare + 30), height: NotchViewModel.openSize.height + 30)
            : CGSize(width: vm.closedBody.width + 2 * NotchViewModel.flare, height: g.notchSize.height)
        panel.setFrame(CGRect(x: g.screenFrame.midX - size.width / 2, y: g.screenFrame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// Окно ловит мышь только над самой чёлкой, чтобы не мешать меню-бару рядом.
    /// Исключение: пока кнопка зажата (значит, что-то тащат), верхняя полоса экрана
    /// принимает события заранее — иначе файл «проезжает» мимо чёлки.
    func updateMouse(_ m: CGPoint) {
        let hot = vm.isOpen ? vm.openRect.insetBy(dx: -12, dy: -12) : vm.closedRect
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        let nearTop = dragging && m.y > vm.geometry.screenFrame.maxY - 120
            && abs(m.x - vm.geometry.screenFrame.midX) < vm.closedBody.width
        let wants = hot.contains(m) || nearTop || vm.isDragOver
        if panel.ignoresMouseEvents == wants { panel.ignoresMouseEvents = !wants }
        // Уровень НЕ поднимаем: окна выше системного drag-слоя не могут быть целью перетаскивания.
    }

    func refreshGeometry(_ g: NotchGeometry) {
        vm.geometry = g
        applyFrame(open: vm.contentMounted)
    }
}


/// Невидимое окно-ловушка для перетаскивания: появляется над чёлкой только пока
/// в системе тащат что-то с зажатой кнопкой, и исчезает сразу после. Обычное окно
/// без хитрых флагов — системе не к чему придраться.
@MainActor
final class DropCatcher {
    let window: NSWindow
    private let drop = DropView(frame: .zero)

    init(vm: NotchViewModel, shelf: ShelfStore) {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        drop.name = "чёлка"
        window.contentView = drop
        drop.onEnter = {
            vm.isDragOver = true
            vm.tab = .shelf
            vm.open()
        }
        drop.onExit = { vm.isDragOver = false }
        drop.onDropURLs = { [weak self] urls in
            vm.isDragOver = false
            self?.disarm()
            guard !urls.isEmpty else { return false }
            shelf.add(urls)
            vm.tab = .shelf
            vm.open()
            return true
        }
    }

    /// Показать ловушку над зоной чёлки (или раскрытой панели).
    func arm(over rect: CGRect) {
        if window.frame != rect { window.setFrame(rect, display: false) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func disarm() {
        if window.isVisible { window.orderOut(nil) }
    }
}

/// Приём файлов, брошенных на чёлку. SwiftUI-овый onDrop в окне поверх меню-бара не срабатывает,
/// поэтому целью перетаскивания служит обычный NSView.
func dropLog(_ text: String) {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AndreichNotch", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = dir.appendingPathComponent("drop.log")
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(text)\n"
    if let h = try? FileHandle(forWritingTo: f) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: f, atomically: true, encoding: .utf8) }
}

final class DropView: NSView {
    var name = "чёлка"
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    var onDropURLs: ([URL]) -> Bool = { _ in false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropLog("вошёл \(name)")
        MainActor.assumeIsolated { onEnter() }
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { MainActor.assumeIsolated { onExit() } }
    override func draggingEnded(_ sender: NSDraggingInfo) { MainActor.assumeIsolated { onExit() } }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        dropLog("бросили \(name): \(urls.count) шт. \(urls.map(\.lastPathComponent).joined(separator: ", "))")
        return MainActor.assumeIsolated { onDropURLs(urls) }
    }
}
