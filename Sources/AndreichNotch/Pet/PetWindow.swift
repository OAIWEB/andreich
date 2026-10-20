import AppKit
import SwiftUI

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Чтобы первый клик по нажимаемому окну доходил до SwiftUI без активации приложения.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SpeechBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color.white))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

struct PetSpriteView: View {
    @ObservedObject var brain: PetBrain
    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle().inset(by: 36))
                .onTapGesture { brain.poke() }
            if let b = brain.bubble, abs(brain.rotation) < 1 {
                SpeechBubble(text: b).offset(y: -68)
            }
        }
        .frame(width: PetWindowController.size, height: PetWindowController.size)
    }
}

/// Маленькое прозрачное окно с Андреичем, которое двигается по экрану.
/// Ловит мышь только когда курсор над ним, остальное время прозрачно для кликов.
@MainActor
final class PetWindowController {
    static let size: CGFloat = 150
    let panel: PetPanel
    private let brain: PetBrain

    init(brain: PetBrain, shelf: ShelfStore) {
        self.brain = brain
        let s = Self.size
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: s, height: s),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        let rootView = DropView(frame: NSRect(x: 0, y: 0, width: s, height: s))
        rootView.name = "Андреич"
        rootView.onDropURLs = { urls in
            guard !urls.isEmpty else { return false }
            shelf.add(urls)
            return true
        }
        let slot = NSView(frame: rootView.bounds); slot.autoresizingMask = [.width, .height]; slot.wantsLayer = true
        rootView.addSubview(slot)
        RaccoonWeb.shared.slots["overlay"] = slot
        let host = FirstMouseHostingView(rootView: PetSpriteView(brain: brain))
        host.sizingOptions = []
        host.frame = rootView.bounds; host.autoresizingMask = [.width, .height]
        rootView.addSubview(host)
        panel.contentView = rootView
    }

    func sync(mouse: CGPoint) {
        if brain.mode == .home || brain.mode == .entering && brain.scale < 0.35 {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let s = Self.size
        panel.setFrameOrigin(CGPoint(x: brain.position.x - s / 2, y: brain.position.y - s / 2))
        if !panel.isVisible { panel.orderFrontRegardless() }
        let hit = CGRect(x: brain.position.x - 38, y: brain.position.y - 44, width: 76, height: 92)
        let wantsMouse = hit.contains(mouse) && brain.mode == .roaming
        if panel.ignoresMouseEvents == wantsMouse { panel.ignoresMouseEvents = !wantsMouse }
    }

    func hide() { panel.orderOut(nil) }
}
