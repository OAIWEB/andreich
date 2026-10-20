import SwiftUI

enum PetPose: Equatable { case sleep, idle, walk, work, cheer, wave, sit, listen }

/// Андреич, нарисованный кодом (временный образ: усатый мастер в кепке).
/// Настоящую графику можно подменить, не трогая поведение.
struct AndreichView: View {
    var pose: PetPose
    var facing: CGFloat = 1
    var size: CGFloat = 96

    var body: some View {
        if true {
            CyberRaccoonView(pose: pose, facing: facing, size: size)
        } else {
            TimelineView(.animation(minimumInterval: AndreichArt.frameInterval(pose))) { tl in
                Canvas { ctx, sz in
                    AndreichArt.draw(ctx, size: sz, pose: pose, t: tl.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(x: facing, y: 1)
        }
    }
}

enum AndreichArt {
    /// Чем спокойнее поза, тем реже перерисовка: спящий в чёлке почти ничего не стоит.
    static func frameInterval(_ pose: PetPose) -> TimeInterval {
        switch pose {
        case .sleep: return 0.5
        case .work: return 1.0 / 12
        case .idle, .sit, .wave: return 1.0 / 20
        case .listen: return 1.0 / 15
        case .walk, .cheer: return 1.0 / 30
        }
    }
    static let skin = Color(red: 0.96, green: 0.80, blue: 0.64)
    static let skinDark = Color(red: 0.90, green: 0.66, blue: 0.52)
    static let cap = Color(red: 0.29, green: 0.33, blue: 0.40)
    static let capDark = Color(red: 0.20, green: 0.23, blue: 0.29)
    static let mustache = Color(red: 0.48, green: 0.32, blue: 0.19)
    static let overall = Color(red: 0.24, green: 0.43, blue: 0.71)
    static let overallLight = Color(red: 0.31, green: 0.51, blue: 0.80)
    static let shirt = Color(red: 0.93, green: 0.90, blue: 0.84)
    static let boot = Color(red: 0.18, green: 0.15, blue: 0.14)
    static let ink = Color(red: 0.10, green: 0.09, blue: 0.10)

    private static func ell(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                            _ color: Color, rot: Double = 0) {
        var c = ctx
        c.translateBy(x: x, y: y)
        c.rotate(by: .degrees(rot))
        c.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: .color(color))
    }

    private static func rrect(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                              _ r: Double, _ color: Color) {
        ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), cornerRadius: r),
                 with: .color(color))
    }

    private static func arm(_ ctx: GraphicsContext, _ x: Double, _ y: Double, _ angle: Double, tool: Bool = false) {
        var c = ctx
        c.translateBy(x: x, y: y)
        c.rotate(by: .degrees(angle))
        if tool {
            c.fill(Path(roundedRect: CGRect(x: -1.8, y: 18, width: 3.6, height: 17), cornerRadius: 1.8), with: .color(.gray))
            c.fill(Path(ellipseIn: CGRect(x: -5, y: 31, width: 10, height: 8)), with: .color(Color(white: 0.7)))
        }
        c.fill(Path(ellipseIn: CGRect(x: -5.5, y: -3, width: 11, height: 22)), with: .color(overall))
        c.fill(Path(ellipseIn: CGRect(x: -4.5, y: 15, width: 9, height: 9)), with: .color(skin))
    }

    static func draw(_ base: GraphicsContext, size: CGSize, pose: PetPose, t rawT: Double) {
        let t = pose == .sleep ? (rawT * 2).rounded(.down) / 2 : rawT   // сон: ступеньки по 0,5 с
        var ctx = base
        let s = min(size.width, size.height) / 100
        ctx.scaleBy(x: s, y: s)

        let phase = t * 9
        let walking = pose == .walk
        let bob: Double
        switch pose {
        case .walk: bob = -abs(sin(phase)) * 3
        case .cheer: bob = -abs(sin(t * 7)) * 16
        case .sit: bob = 7
        case .sleep: bob = 9
        case .idle, .wave, .work, .listen: bob = sin(t * 2.2) * 0.8
        }
        let jump = pose == .cheer ? -bob : 0

        // тень
        ell(ctx, 50, 96, pose == .cheer ? 34 : 46, 7, .black.opacity(0.28))

        // ноги
        if pose == .sit || pose == .sleep {
            rrect(ctx, 34, 92, 17, 8, 4, boot); rrect(ctx, 66, 92, 17, 8, 4, boot)
        } else {
            let l1 = walking ? max(0, sin(phase)) * 6 : 0
            let l2 = walking ? max(0, -sin(phase)) * 6 : 0
            rrect(ctx, 39, 89 - l1 - jump, 14, 11, 4, boot)
            rrect(ctx, 61, 89 - l2 - jump, 14, 11, 4, boot)
        }

        // туловище: комбинезон
        let by = 68 + bob * 0.55
        ell(ctx, 50, by, 46, 40, overall)
        ell(ctx, 50, by - 12, 28, 14, shirt)
        rrect(ctx, 50, by + 1, 24, 18, 5, overallLight)
        ell(ctx, 43, by - 5, 3.2, 3.2, Color(red: 0.98, green: 0.82, blue: 0.3))
        ell(ctx, 57, by - 5, 3.2, 3.2, Color(red: 0.98, green: 0.82, blue: 0.3))

        // руки
        let sway = sin(t * 2.2) * 3
        switch pose {
        case .walk:
            arm(ctx, 29, by - 8, sin(phase) * 28); arm(ctx, 71, by - 8, -sin(phase) * 28)
        case .wave:
            arm(ctx, 29, by - 8, 4 + sway); arm(ctx, 71, by - 8, -140 + sin(t * 12) * 18)
        case .cheer:
            arm(ctx, 29, by - 8, 150 - sin(t * 10) * 10); arm(ctx, 71, by - 8, -150 + sin(t * 10) * 10)
        case .work:
            arm(ctx, 29, by - 8, 6 + sway); arm(ctx, 71, by - 8, -62 + sin(t * 8) * 34, tool: true)
        case .sit, .sleep:
            arm(ctx, 30, by - 6, 8); arm(ctx, 70, by - 6, -8)
        case .idle:
            arm(ctx, 29, by - 8, 5 + sway); arm(ctx, 71, by - 8, -5 - sway)
        case .listen:
            arm(ctx, 29, by - 8, 158 + sin(t * 3) * 3); arm(ctx, 71, by - 8, -5 - sway)
        }

        // голова (относительные координаты)
        var h = ctx
        h.translateBy(x: 50, y: 38 + bob)
        let tilt: Double = pose == .sleep ? 9 : (pose == .cheer ? sin(t * 7) * 6 : 0)
        h.rotate(by: .degrees(tilt))

        ell(h, -24, 3, 10, 12, skin); ell(h, 24, 3, 10, 12, skin)
        ell(h, 0, 0, 50, 48, skin)
        ell(h, -15, 9, 9, 6, Color(red: 0.95, green: 0.55, blue: 0.5).opacity(0.5))
        ell(h, 15, 9, 9, 6, Color(red: 0.95, green: 0.55, blue: 0.5).opacity(0.5))

        // глаза
        let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.12
        for ex in [-9.0, 9.0] {
            if pose == .sleep || blink {
                var p = Path(); p.move(to: CGPoint(x: ex - 4, y: 3)); p.addQuadCurve(to: CGPoint(x: ex + 4, y: 3), control: CGPoint(x: ex, y: 6.5))
                h.stroke(p, with: .color(ink), lineWidth: 1.7)
            } else if pose == .cheer {
                var p = Path(); p.move(to: CGPoint(x: ex - 4, y: 4)); p.addQuadCurve(to: CGPoint(x: ex + 4, y: 4), control: CGPoint(x: ex, y: -2))
                h.stroke(p, with: .color(ink), lineWidth: 1.9)
            } else {
                ell(h, ex, 3, 5, 6.5, ink)
                ell(h, ex + 1, 1.2, 1.8, 1.8, .white)
            }
        }
        ell(h, 0, 7, 7, 6, skinDark)                               // нос
        ell(h, -8, 13, 18, 9, mustache, rot: 12)                   // усы
        ell(h, 8, 13, 18, 9, mustache, rot: -12)
        ell(h, 0, 11, 10, 6, mustache)
        if pose == .cheer { ell(h, 0, 20, 8, 5, Color(red: 0.55, green: 0.15, blue: 0.15)) }

        // кепка
        ell(h, 0, -20, 52, 22, cap)
        rrect(h, 0, -11, 52, 5, 2.5, capDark)
        ell(h, 17, -10, 28, 8, capDark)
        ell(h, 0, -31, 5, 5, capDark)

        // звуковые волны у уха, пока слушает
        if pose == .listen {
            for i in 0..<3 {
                let p = (t * 1.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                var c = ctx
                c.opacity = (1 - p) * 0.9
                var arc = Path()
                let r = 6 + p * 10
                arc.addArc(center: CGPoint(x: 21, y: 36 + bob), radius: r, startAngle: .degrees(130), endAngle: .degrees(230), clockwise: false)
                c.stroke(arc, with: .color(.white), lineWidth: 1.8)
            }
        }

        // «z-z-z» во сне
        if pose == .sleep {
            for i in 0..<3 {
                let p = (t * 0.55 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                var c = ctx
                c.opacity = (1 - p) * 0.95
                c.draw(Text("z").font(.system(size: 11 + Double(i) * 2, weight: .bold, design: .rounded)).foregroundColor(.white),
                       at: CGPoint(x: 70 + p * 12 + Double(i) * 3, y: 30 - p * 26))
            }
        }
    }
}
