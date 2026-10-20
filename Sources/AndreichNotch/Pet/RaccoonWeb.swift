import AppKit
import SwiftUI
import WebKit

/// WebGL-окно с 3D-Андреичем. Не ловит мышь: клики проходят к SwiftUI поверх.
final class PassthroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Один экземпляр 3D-енота на всё приложение. Он переезжает между «местами»:
/// чёлка (крупно голова), раскрытая панель и окно прогулки по экрану.
@MainActor
final class RaccoonWeb: NSObject, WKNavigationDelegate {
    static let shared = RaccoonWeb()
    let web: PassthroughWebView
    var slots: [String: NSView] = [:]
    private var loaded = false
    private var queue: [String] = []
    private var sent: [String: String] = [:]

    private override init() {
        let cfg = WKWebViewConfiguration()
        web = PassthroughWebView(frame: NSRect(x: 0, y: 0, width: 120, height: 120), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        super.init()
        web.navigationDelegate = self
        if let url = Bundle.main.url(forResource: "app", withExtension: "html", subdirectory: "web") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded = true
            for js in queue { web.evaluateJavaScript(js) }
            queue.removeAll()
        }
    }

    private func send(_ key: String, _ js: String) {
        guard sent[key] != js else { return }
        sent[key] = js
        if loaded { web.evaluateJavaScript(js) } else { queue.append(js) }
    }

    /// Вид Андреича: "mini" — кругляш (по умолчанию), "full" — в полный рост. Запоминается.
    private(set) var variant = UserDefaults.standard.string(forKey: "raccoonVariant") ?? "mini"
    func setVariant(_ v: String) {
        variant = v
        UserDefaults.standard.set(v, forKey: "raccoonVariant")
        send("variant", "A.setVariant('\(v)')")
    }
    func applySavedVariant() { send("variant", "A.setVariant('\(variant)')") }

    func update(state: String, facing: Int, rotation: Double, scale: Double, view: String, fps: Int) {
        send("state", "A.setState('\(state)')")
        send("facing", "A.setFacing(\(facing))")
        send("rot", "A.setRotation(\(Int(rotation.rounded())))")
        send("scale", "A.setScale(\(String(format: "%.2f", scale)))")
        send("view", "A.setView('\(view)')")
        send("fps", "A.setFPS(\(fps))")
    }

    func attach(slot name: String) {
        guard let c = slots[name], c.window != nil else { return }
        if web.superview !== c {
            web.removeFromSuperview()
            web.frame = c.bounds
            web.autoresizingMask = [.width, .height]
            c.addSubview(web, positioned: .below, relativeTo: nil)
        }
    }
}

/// Место в SwiftUI, куда может «сесть» енот.
struct RaccoonSlot: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView(); v.wantsLayer = true
        RaccoonWeb.shared.slots[name] = v
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { RaccoonWeb.shared.slots[name] = v }
    static func dismantleNSView(_ v: NSView, coordinator: ()) {
        MainActor.assumeIsolated {
            for (k, s) in RaccoonWeb.shared.slots where s === v { RaccoonWeb.shared.slots[k] = nil }
        }
    }
}

extension PetPose {
    var js: String {
        switch self {
        case .sleep: return "sleep"; case .idle: return "idle"; case .walk: return "walk"; case .work: return "work"
        case .cheer: return "cheer"; case .wave: return "wave"; case .sit: return "sit"; case .listen: return "listen"
        }
    }
}
