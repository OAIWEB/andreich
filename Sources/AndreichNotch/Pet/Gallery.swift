import AppKit
import SwiftUI

/// Отладка: ANDREICH_GALLERY=1 открывает окно со всеми позами крупно.
struct PoseGallery: View {
    let poses: [(String, PetPose)] = [("walk", .walk), ("idle", .idle), ("listen", .listen), ("wave", .wave),
                                      ("cheer", .cheer), ("work", .work), ("sit", .sit), ("sleep", .sleep)]
    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(220)), count: 4), spacing: 8) {
                ForEach(poses, id: \.0) { name, pose in
                    VStack(spacing: 0) {
                        AndreichView(pose: pose, facing: 1, size: 210).background(Color(white: 0.09))
                        Text(name).font(.caption).foregroundColor(.gray)
                    }
                }
            }
            HStack(spacing: 20) {
                AndreichView(pose: .listen, size: 30).background(Color.black)
                AndreichView(pose: .sleep, size: 30).background(Color.black)
                AndreichView(pose: .work, size: 30).background(Color.black)
                AndreichView(pose: .walk, facing: -1, size: 112).background(Color(white: 0.09))
                AndreichView(pose: .idle, size: 112).background(Color(white: 0.09))
            }
        }
        .padding(12).background(Color(white: 0.04))
    }
}

@MainActor
func showPoseGallery() -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 40, y: 80, width: 940, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: PoseGallery())
    w.title = "Позы Андреича"
    w.level = .floating
    w.orderFrontRegardless()
    return w
}
