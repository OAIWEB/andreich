import AppKit

/// Где на экране находится чёлка. Если выреза нет (внешний монитор), рисуем «виртуальную».
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var visibleFrame: CGRect
    var notchSize: CGSize
    var hasHardwareNotch: Bool

    var notchRect: CGRect {
        CGRect(x: screenFrame.midX - notchSize.width / 2,
               y: screenFrame.maxY - notchSize.height,
               width: notchSize.width, height: notchSize.height)
    }

    static func current() -> NotchGeometry? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return nil }
        let f = screen.frame
        if screen.safeAreaInsets.top > 0 {
            var w: CGFloat = 190
            if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
                w = f.width - l.width - r.width
            }
            return NotchGeometry(screenFrame: f, visibleFrame: screen.visibleFrame,
                                 notchSize: CGSize(width: w, height: screen.safeAreaInsets.top),
                                 hasHardwareNotch: true)
        }
        let bar = max(24, f.maxY - screen.visibleFrame.maxY)
        return NotchGeometry(screenFrame: f, visibleFrame: screen.visibleFrame,
                             notchSize: CGSize(width: 190, height: bar), hasHardwareNotch: false)
    }
}
