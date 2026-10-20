import SwiftUI

/// Андреич-киберенот: рисуется кодом по листу-образцу, части двигаются сами
/// (ноги, руки, хвост с бирюзовыми кольцами, плащ, уши, визор).
struct CyberRaccoonView: View {
    var pose: PetPose
    var facing: CGFloat = 1
    var size: CGFloat = 112
    private var small: Bool { size <= 44 }

    var body: some View {
        TimelineView(.animation(minimumInterval: AndreichArt.frameInterval(pose))) { tl in
            Canvas { ctx, sz in
                let raw = tl.date.timeIntervalSinceReferenceDate
                let t = pose == .sleep ? (raw * 2).rounded(.down) / 2 : raw
                CyberRaccoonArt.draw(ctx, size: sz, pose: pose, t: t, small: small)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: facing, y: 1)
    }
}

enum CyberRaccoonArt {
    // палитра
    static let tiffany = Color(red: 0.04, green: 0.73, blue: 0.71)
    static let glow = Color(red: 0.30, green: 0.97, blue: 0.92)
    static let red = Color(red: 0.90, green: 0.07, blue: 0.11)
    static let redDark = Color(red: 0.60, green: 0.04, blue: 0.08)
    static let fur = Color(red: 0.58, green: 0.58, blue: 0.63)
    static let furLight = Color(red: 0.85, green: 0.85, blue: 0.89)
    static let furDark = Color(red: 0.27, green: 0.27, blue: 0.31)
    static let mask = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let jacket = Color(red: 0.13, green: 0.13, blue: 0.16)
    static let jacketLight = Color(red: 0.24, green: 0.24, blue: 0.29)
    static let metal = Color(red: 0.69, green: 0.72, blue: 0.77)
    static let metalDark = Color(red: 0.36, green: 0.39, blue: 0.44)
    static let boot = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let pants = Color(red: 0.20, green: 0.20, blue: 0.24)

    enum Eyes { case open, closed, happy }

    struct Rig {
        var bob = 0.0, lean = 0.0, headTilt = 0.0
        var legA = (0.0, 0.0), legB = (0.0, 0.0)        // бедро, колено (от вертикали вниз, + вперёд)
        var armA = (0.0, 0.0), armB = (0.0, 0.0)        // плечо, локоть
        var mouth = 0.0
        var eyes = Eyes.open
        var sit = false
        var flutter = 1.0, tailAmp = 1.0, tailSpeed = 2.2
        var panel = false, waves = false, sparkles = false
        var drop = 0.0                                  // опустить корпус (сидит/спит)
    }

    static func rig(_ pose: PetPose, _ t: Double) -> Rig {
        var r = Rig()
        let breathe = sin(t * 2.2)
        switch pose {
        case .walk:
            let ph = t * 11
            r.bob = -abs(sin(ph)) * 4; r.lean = 0.09
            r.legA = (0.75 * sin(ph), -max(0, cos(ph)) * 1.0)
            r.legB = (0.75 * sin(ph + .pi), -max(0, cos(ph + .pi)) * 1.0)
            r.armA = (-0.9 * sin(ph), 0.9); r.armB = (0.9 * sin(ph), 0.9)
            r.flutter = 2.2; r.tailAmp = 1.5; r.tailSpeed = 6
        case .idle:
            r.bob = breathe * 0.8
            r.armA = (0.12 + breathe * 0.03, 0.3); r.armB = (-0.08, 0.35)
            r.legA = (0.06, 0); r.legB = (-0.08, 0)
        case .listen:
            r.bob = breathe * 0.6; r.headTilt = 0.1; r.waves = true
            r.armA = (2.55, -2.1); r.armB = (-0.08, 0.35)
            r.legA = (0.06, 0); r.legB = (-0.08, 0)
        case .wave:
            r.bob = breathe * 0.6
            r.armA = (2.5, -0.4 + 0.55 * sin(t * 11)); r.armB = (-0.08, 0.35)
            r.legA = (0.06, 0); r.legB = (-0.08, 0); r.mouth = 0.4
        case .cheer:
            r.bob = -abs(sin(t * 7)) * 26; r.headTilt = sin(t * 7) * 0.12
            r.armA = (2.7 + 0.15 * sin(t * 14), -0.2); r.armB = (-2.7 - 0.15 * sin(t * 14), 0.2)
            r.legA = (0.5, -1.0); r.legB = (-0.2, -1.1)
            r.mouth = 1; r.eyes = .happy; r.sparkles = true; r.flutter = 2.4; r.tailAmp = 1.8; r.tailSpeed = 7
        case .work:
            r.bob = sin(t * 8) * 0.6; r.panel = true; r.headTilt = 0.04
            r.armA = (1.3, 0.25 + 0.25 * sin(t * 9)); r.armB = (1.2, 0.35 + 0.25 * sin(t * 9 + 1.5))
            r.legA = (0.06, 0); r.legB = (-0.08, 0)
        case .sit:
            r.sit = true; r.drop = 40; r.bob = breathe * 0.6
            r.legA = (1.45, -1.3); r.legB = (1.25, -1.2)
            r.armA = (0.4, 0.3); r.armB = (0.2, 0.5)
        case .sleep:
            r.sit = true; r.drop = 44; r.eyes = .closed; r.headTilt = 0.38; r.bob = sin(t * 2) * 0.6
            r.legA = (1.5, -1.5); r.legB = (1.35, -1.45)
            r.armA = (0.9, 1.6); r.armB = (0.7, 1.8)
            r.flutter = 0.3; r.tailAmp = 0.3; r.tailSpeed = 1
        }
        return r
    }

    // MARK: помощники
    static func ell(_ c: GraphicsContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ shade: GraphicsContext.Shading, rot: Double = 0) {
        var d = c; d.translateBy(x: x, y: y); d.rotate(by: .radians(rot))
        d.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)), with: shade)
    }
    static func seg(_ c: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ w: Double, _ color: Color) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }
    static func fk(_ o: CGPoint, _ a1: Double, _ l1: Double, _ a2: Double, _ l2: Double) -> (CGPoint, CGPoint) {
        let k = CGPoint(x: o.x + l1 * sin(a1), y: o.y + l1 * cos(a1))
        return (k, CGPoint(x: k.x + l2 * sin(a1 + a2), y: k.y + l2 * cos(a1 + a2)))
    }
    static func glowing(_ c: GraphicsContext, radius: Double = 3.5, _ draw: (GraphicsContext) -> Void) {
        var g = c; g.addFilter(.shadow(color: glow.opacity(0.9), radius: radius)); draw(g)
    }

    // MARK: главный рисунок
    static func draw(_ base: GraphicsContext, size: CGSize, pose: PetPose, t: Double, small: Bool) {
        var ctx = base
        let s = min(size.width, size.height) / 200
        ctx.scaleBy(x: s, y: s)
        let r = rig(pose, t)

        if small {   // крошечная чёлка: только голова крупно
            ctx.translateBy(x: 100, y: 100); ctx.scaleBy(x: 2.9, y: 2.9); ctx.translateBy(x: -122, y: -50)
            drawHead(ctx, r, t, pose)
            return
        }

        let pelvis = CGPoint(x: 100, y: 130 + r.bob + r.drop)
        let hipA = CGPoint(x: pelvis.x + 8, y: pelvis.y + 6 - r.drop * 0.0)
        let hipB = CGPoint(x: pelvis.x - 6, y: pelvis.y + 6)
        let airborne = pose == .cheer ? -r.bob : 0

        // тень
        ell(ctx, 100, 194, pose == .cheer ? 50 : 76, 9, .color(.black.opacity(0.30)))

        // всё, что крепится к корпусу, наклоняем вместе с ним
        var body = ctx
        body.translateBy(x: pelvis.x, y: pelvis.y); body.rotate(by: .radians(r.lean)); body.translateBy(x: -pelvis.x, y: -pelvis.y)
        body.translateBy(x: 0, y: r.drop * 0.0)

        drawCape(body, r, t, pelvis)
        drawTail(body, r, t, pelvis)

        // дальние конечности (темнее)
        drawLeg(ctx, hipB, r.legB, near: false, sit: r.sit, lift: airborne, ground: 194)
        drawArm(body, CGPoint(x: 104, y: 86 + r.bob + r.drop), r.armB, near: false, t: t)

        drawTorso(body, r, t, pelvis)
        drawLeg(ctx, hipA, r.legA, near: true, sit: r.sit, lift: airborne, ground: 194)

        var headCtx = body
        let neck = CGPoint(x: 112, y: 70 + r.bob + r.drop)
        headCtx.translateBy(x: neck.x, y: neck.y); headCtx.rotate(by: .radians(r.headTilt)); headCtx.translateBy(x: -neck.x, y: -neck.y)
        headCtx.translateBy(x: 0, y: r.bob + r.drop)
        drawHead(headCtx, r, t, pose)

        drawArm(body, CGPoint(x: 112, y: 88 + r.bob + r.drop), r.armA, near: true, t: t)

        if r.panel { drawPanel(ctx, t, r) }
        if r.waves { drawWaves(ctx, t, r) }
        if r.sparkles { drawSparkles(ctx, t) }
        if pose == .sleep { drawZ(ctx, t) }
    }

    // MARK: плащ
    static func drawCape(_ c: GraphicsContext, _ r: Rig, _ t: Double, _ p: CGPoint) {
        let f = r.flutter
        let w1 = sin(t * 5.0) * 6 * f, w2 = sin(t * 5.0 + 1.3) * 8 * f, w3 = sin(t * 4.2 + 2.1) * 5 * f
        let top = 78 + r.bob + r.drop
        var cape = Path()
        cape.move(to: CGPoint(x: 100, y: top))
        cape.addQuadCurve(to: CGPoint(x: 52 + w1, y: top + 36 + w2), control: CGPoint(x: 76, y: top - 4 + w3))
        cape.addQuadCurve(to: CGPoint(x: 66 + w1 * 0.5, y: top + 74 + w2), control: CGPoint(x: 46 + w1, y: top + 62))
        cape.addQuadCurve(to: CGPoint(x: 100, y: top + 52), control: CGPoint(x: 86, y: top + 76 + w3))
        cape.closeSubpath()
        c.fill(cape, with: .linearGradient(Gradient(colors: [red, redDark]), startPoint: CGPoint(x: 100, y: top), endPoint: CGPoint(x: 52, y: top + 70)))
        // складка
        var fold = Path(); fold.move(to: CGPoint(x: 98, y: top + 6)); fold.addQuadCurve(to: CGPoint(x: 62 + w1 * 0.7, y: top + 62 + w2 * 0.6), control: CGPoint(x: 78, y: top + 34))
        c.stroke(fold, with: .color(redDark.opacity(0.55)), lineWidth: 1.4)
        // эмблема OAI WEB
        var e = c
        e.translateBy(x: 74 + w1 * 0.5, y: top + 34 + w2 * 0.35); e.rotate(by: .radians(-0.35 + sin(t * 4) * 0.08 * f))
        e.fill(Path(roundedRect: CGRect(x: -15, y: -10, width: 30, height: 21), cornerRadius: 4), with: .color(Color(red: 0.08, green: 0.06, blue: 0.06)))
        var slash = Path(); slash.move(to: CGPoint(x: -4, y: 9)); slash.addLine(to: CGPoint(x: 5, y: -8)); slash.addLine(to: CGPoint(x: 10, y: -8)); slash.addLine(to: CGPoint(x: 1, y: 9)); slash.closeSubpath()
        e.fill(slash, with: .color(red))
        ell(e, 9, -3.5, 4.2, 4.2, .color(Color(red: 0.93, green: 0.90, blue: 0.84)))
        e.draw(Text("OAI WEB").font(.system(size: 5.2, weight: .heavy)).foregroundColor(.white), at: CGPoint(x: -4, y: -2))
    }

    // MARK: хвост
    static func drawTail(_ c: GraphicsContext, _ r: Rig, _ t: Double, _ p: CGPoint) {
        let base = CGPoint(x: 86, y: 128 + r.bob + r.drop)
        let p1 = CGPoint(x: 52, y: 142 + r.drop * 0.3), p2 = CGPoint(x: 24, y: 118), p3 = CGPoint(x: 26, y: 82)
        let n = 9
        var pts: [CGPoint] = []
        for i in 0...n {
            let u = Double(i) / Double(n), v = 1 - u
            var x = v*v*v*base.x + 3*v*v*u*p1.x + 3*v*u*u*p2.x + u*u*u*p3.x
            var y = v*v*v*base.y + 3*v*v*u*p1.y + 3*v*u*u*p2.y + u*u*u*p3.y
            let sway = sin(t * r.tailSpeed - u * 3.2) * 9 * r.tailAmp * u
            x += sway * 0.35; y += sway
            pts.append(CGPoint(x: x, y: y))
        }
        for i in stride(from: n, through: 0, by: -1) {
            let u = Double(i) / Double(n)
            let rad = 13.5 - 5 * u
            let ring = i % 2 == 1
            if ring {
                glowing(c, radius: 3) { g in ell(g, pts[i].x, pts[i].y, rad * 1.7, rad * 1.7, .color(tiffany)) }
                ell(c, pts[i].x, pts[i].y, rad * 1.35, rad * 1.35, .color(glow.opacity(0.9)))
            } else {
                ell(c, pts[i].x, pts[i].y, rad * 2.0, rad * 2.0, .color(furDark))
                ell(c, pts[i].x - 1.5, pts[i].y - 1.5, rad * 1.3, rad * 1.3, .color(Color(red: 0.36, green: 0.36, blue: 0.41)))
            }
        }
    }

    // MARK: ноги
    static func drawLeg(_ c: GraphicsContext, _ hip: CGPoint, _ a: (Double, Double), near: Bool, sit: Bool, lift: Double, ground: Double) {
        let pant = near ? pants : pants.opacity(0.78)
        let (knee, ankle) = fk(CGPoint(x: hip.x, y: hip.y - lift * 0.4), a.0, 24, a.1, 24)
        seg(c, CGPoint(x: hip.x, y: hip.y - lift * 0.4), knee, 15, pant)
        seg(c, knee, ankle, 13, pant)
        // ботинок
        var b = c
        b.translateBy(x: ankle.x + 4, y: ankle.y + 2)
        b.rotate(by: .radians(a.0 + a.1) * 0.55)
        b.fill(Path(roundedRect: CGRect(x: -12, y: -6, width: 28, height: 13), cornerRadius: 6), with: .color(near ? boot : boot.opacity(0.85)))
        b.fill(Path(roundedRect: CGRect(x: -12, y: 4, width: 28, height: 4), cornerRadius: 2), with: .color(Color(red: 0.2, green: 0.2, blue: 0.24)))
        var cyan = Path(); cyan.move(to: CGPoint(x: -8, y: 2)); cyan.addLine(to: CGPoint(x: 8, y: 2))
        if near { b.stroke(cyan, with: .color(tiffany.opacity(0.9)), lineWidth: 1.2) }
    }

    // MARK: туловище
    static func drawTorso(_ c: GraphicsContext, _ r: Rig, _ t: Double, _ p: CGPoint) {
        let dy = r.bob + r.drop
        var j = Path()
        j.move(to: CGPoint(x: 84, y: 84 + dy))
        j.addQuadCurve(to: CGPoint(x: 102, y: 72 + dy), control: CGPoint(x: 90, y: 72 + dy))
        j.addQuadCurve(to: CGPoint(x: 126, y: 82 + dy), control: CGPoint(x: 118, y: 70 + dy))
        j.addQuadCurve(to: CGPoint(x: 124, y: 124 + dy), control: CGPoint(x: 134, y: 102 + dy))
        j.addQuadCurve(to: CGPoint(x: 116, y: 142 + dy), control: CGPoint(x: 124, y: 138 + dy))
        j.addLine(to: CGPoint(x: 90, y: 142 + dy))
        j.addQuadCurve(to: CGPoint(x: 84, y: 84 + dy), control: CGPoint(x: 72, y: 114 + dy))
        c.fill(j, with: .linearGradient(Gradient(colors: [jacketLight, jacket]), startPoint: CGPoint(x: 96, y: 74 + dy), endPoint: CGPoint(x: 100, y: 142 + dy)))
        c.stroke(j, with: .color(.black.opacity(0.5)), lineWidth: 1.2)
        // бирюзовый кант на молнии и подоле
        glowing(c, radius: 2.5) { g in
            var zip = Path(); zip.move(to: CGPoint(x: 118, y: 84 + dy)); zip.addQuadCurve(to: CGPoint(x: 117, y: 140 + dy), control: CGPoint(x: 124, y: 112 + dy))
            g.stroke(zip, with: .color(tiffany), lineWidth: 1.8)
            var hem = Path(); hem.move(to: CGPoint(x: 90, y: 140 + dy)); hem.addLine(to: CGPoint(x: 114, y: 140 + dy))
            g.stroke(hem, with: .color(tiffany.opacity(0.8)), lineWidth: 1.4)
        }
        // карманы и ремень
        c.stroke(Path(roundedRect: CGRect(x: 104, y: 100 + dy, width: 12, height: 10), cornerRadius: 2), with: .color(jacketLight), lineWidth: 1.1)
        c.stroke(Path(roundedRect: CGRect(x: 90, y: 104 + dy, width: 11, height: 9), cornerRadius: 2), with: .color(jacketLight.opacity(0.8)), lineWidth: 1.1)
        seg(c, CGPoint(x: 96, y: 78 + dy), CGPoint(x: 112, y: 132 + dy), 3.2, jacketLight.opacity(0.8))
        // красный воротник плаща
        var col = Path(); col.move(to: CGPoint(x: 100, y: 76 + dy)); col.addQuadCurve(to: CGPoint(x: 124, y: 82 + dy), control: CGPoint(x: 112, y: 88 + dy))
        c.stroke(col, with: .color(red), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        // живот-шерсть из-под куртки
        ell(c, 104, 143 + dy, 28, 9, .color(furDark))
    }

    // MARK: рука
    static func drawArm(_ c: GraphicsContext, _ shoulder: CGPoint, _ a: (Double, Double), near: Bool, t: Double) {
        let (elbow, hand) = fk(shoulder, a.0, 22, a.1, 22)
        let sleeve = near ? jacket : jacket.opacity(0.85)
        seg(c, shoulder, elbow, 13, sleeve)
        seg(c, shoulder, elbow, 13, .black.opacity(0.18))
        // киберпредплечье: металл + бирюзовая полоса
        seg(c, elbow, hand, 11, near ? metal : metalDark)
        glowing(c, radius: 2.5) { g in seg(g, CGPoint(x: elbow.x * 0.7 + hand.x * 0.3, y: elbow.y * 0.7 + hand.y * 0.3), CGPoint(x: elbow.x * 0.25 + hand.x * 0.75, y: elbow.y * 0.25 + hand.y * 0.75), 3, near ? tiffany : tiffany.opacity(0.7)) }
        ell(c, hand.x, hand.y, 12, 12, .color(near ? metalDark : Color(red: 0.25, green: 0.27, blue: 0.31)))
        ell(c, hand.x - 1, hand.y - 1, 6, 6, .color(metal.opacity(0.6)))
    }

    // MARK: голова
    static func drawHead(_ c: GraphicsContext, _ r: Rig, _ t: Double, _ pose: PetPose) {
        let hy = 50.0
        // дальнее ухо
        var e1 = c; e1.translateBy(x: 104, y: 30); e1.rotate(by: .radians(-0.35 + sin(t * 0.9) * 0.05))
        ell(e1, 0, 0, 15, 19, .color(furDark)); ell(e1, 0, 1, 8, 11, .color(Color(red: 0.75, green: 0.55, blue: 0.58)))
        // ближнее ухо (подёргивается)
        var e2 = c; e2.translateBy(x: 128, y: 28); e2.rotate(by: .radians(0.3 + (sin(t * 0.7).truncatingRemainder(dividingBy: 1) > 0.97 ? 0.4 : 0) + sin(t * 1.3) * 0.04))
        ell(e2, 0, 0, 15, 19, .color(fur)); ell(e2, 0, 1, 8, 11, .color(Color(red: 0.85, green: 0.62, blue: 0.64)))

        // череп и морда
        ell(c, 117, hy, 56, 48, .linearGradient(Gradient(colors: [furLight, fur]), startPoint: CGPoint(x: 117, y: 26), endPoint: CGPoint(x: 117, y: 76)))
        ell(c, 140, hy + 11, 30, 22, .color(furLight))                       // морда
        // чёрная маска вокруг глаз
        ell(c, 128, hy - 3, 38, 17, .color(mask), rot: -0.1)
        ell(c, 135, hy + 7, 18, 8, .color(furLight))
        ell(c, 126, hy - 17, 20, 8, .color(furLight.opacity(0.95)))        // светлая бровь
        ell(c, 154, hy + 7, 9, 7, .color(Color(red: 0.10, green: 0.09, blue: 0.11)))   // нос
        ell(c, 152, hy + 5.5, 3, 2, .color(.white.opacity(0.5)))

        // глаз
        let blink = t.truncatingRemainder(dividingBy: 3.9) < 0.12
        switch (r.eyes, blink) {
        case (.closed, _), (_, true):
            var p = Path(); p.move(to: CGPoint(x: 126, y: hy - 2)); p.addQuadCurve(to: CGPoint(x: 138, y: hy - 2), control: CGPoint(x: 132, y: hy + 3))
            c.stroke(p, with: .color(glow.opacity(0.9)), lineWidth: 1.8)
        case (.happy, _):
            var p = Path(); p.move(to: CGPoint(x: 126, y: hy)); p.addQuadCurve(to: CGPoint(x: 138, y: hy), control: CGPoint(x: 132, y: hy - 7))
            c.stroke(p, with: .color(glow), lineWidth: 2)
        default:
            ell(c, 132, hy - 2, 10, 9, .color(Color(red: 0.20, green: 0.55, blue: 0.55)))
            ell(c, 133, hy - 2, 5, 6, .color(Color(red: 0.05, green: 0.05, blue: 0.07)))
            ell(c, 134.5, hy - 4, 2.2, 2.2, .color(.white))
        }
        // визор поверх глаза
        var v = c; v.translateBy(x: 132, y: hy - 2); v.rotate(by: .radians(-0.08))
        v.fill(Path(roundedRect: CGRect(x: -14, y: -8, width: 28, height: 16), cornerRadius: 5),
               with: .linearGradient(Gradient(colors: [glow.opacity(0.75), tiffany.opacity(0.55)]), startPoint: CGPoint(x: 0, y: -8), endPoint: CGPoint(x: 0, y: 8)))
        glowing(v, radius: 4) { g in g.stroke(Path(roundedRect: CGRect(x: -14, y: -8, width: 28, height: 16), cornerRadius: 5), with: .color(glow), lineWidth: 1.6) }
        let scan = (sin(t * 3.2) * 0.5 + 0.5) * 22 - 11
        v.fill(Path(CGRect(x: scan - 1, y: -7, width: 2, height: 14)), with: .color(.white.opacity(0.55)))

        // рот
        if r.mouth > 0.3 { ell(c, 148, hy + 15, 11, 6 + 4 * r.mouth, .color(Color(red: 0.45, green: 0.10, blue: 0.12))) }
        else {
            var m = Path(); m.move(to: CGPoint(x: 140, y: hy + 14)); m.addQuadCurve(to: CGPoint(x: 152, y: hy + 12), control: CGPoint(x: 146, y: hy + 19))
            c.stroke(m, with: .color(Color(red: 0.2, green: 0.15, blue: 0.16)), lineWidth: 1.5)
        }
        for k in 0..<2 {
            var w = Path(); w.move(to: CGPoint(x: 150, y: hy + 9 + Double(k) * 3)); w.addLine(to: CGPoint(x: 166, y: hy + 5 + Double(k) * 6))
            c.stroke(w, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
        }

        // наушники: дужка, чашка с бирюзовым кольцом, микрофон
        var band = Path(); band.move(to: CGPoint(x: 111, y: hy - 4)); band.addQuadCurve(to: CGPoint(x: 122, y: hy - 30), control: CGPoint(x: 100, y: hy - 22)); band.addQuadCurve(to: CGPoint(x: 140, y: hy - 20), control: CGPoint(x: 134, y: hy - 34))
        c.stroke(band, with: .color(Color(red: 0.17, green: 0.17, blue: 0.21)), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
        c.stroke(band, with: .color(jacketLight.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        ell(c, 110, hy + 2, 24, 25, .color(Color(red: 0.14, green: 0.14, blue: 0.18)))
        let pulse = 0.75 + 0.25 * sin(t * 3)
        glowing(c, radius: 4) { g in g.stroke(Path(ellipseIn: CGRect(x: 110 - 8.5, y: hy + 2 - 8.5, width: 17, height: 17)), with: .color(glow.opacity(pulse)), lineWidth: 2.4) }
        ell(c, 110, hy + 2, 9, 9, .color(Color(red: 0.06, green: 0.07, blue: 0.09)))
        var mic = Path(); mic.move(to: CGPoint(x: 108, y: hy + 13)); mic.addQuadCurve(to: CGPoint(x: 138, y: hy + 22), control: CGPoint(x: 118, y: hy + 30))
        c.stroke(mic, with: .color(Color(red: 0.17, green: 0.17, blue: 0.21)), lineWidth: 1.6)
        ell(c, 138, hy + 22, 4.5, 4.5, .color(tiffany))
    }

    // MARK: эффекты
    static func drawPanel(_ c: GraphicsContext, _ t: Double, _ r: Rig) {
        var p = c; p.translateBy(x: 160, y: 108 + r.bob)
        p.fill(Path(roundedRect: CGRect(x: -20, y: -16, width: 40, height: 30), cornerRadius: 5), with: .color(tiffany.opacity(0.25)))
        glowing(p, radius: 3) { g in g.stroke(Path(roundedRect: CGRect(x: -20, y: -16, width: 40, height: 30), cornerRadius: 5), with: .color(glow), lineWidth: 1.4) }
        for i in 0..<4 {
            let h = 6 + 8 * abs(sin(t * 3 + Double(i) * 1.1))
            p.fill(Path(CGRect(x: -14 + Double(i) * 8, y: 10 - h, width: 5, height: h)), with: .color(glow.opacity(0.85)))
        }
    }
    static func drawWaves(_ c: GraphicsContext, _ t: Double, _ r: Rig) {
        for i in 0..<3 {
            let p = (t * 1.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var a = Path()
            a.addArc(center: CGPoint(x: 112, y: 52), radius: 22 + p * 22, startAngle: .degrees(195), endAngle: .degrees(255), clockwise: false)
            var g = c; g.opacity = 1 - p
            glowing(g, radius: 3) { gg in gg.stroke(a, with: .color(glow), style: StrokeStyle(lineWidth: 2.2, lineCap: .round)) }
        }
    }
    static func drawSparkles(_ c: GraphicsContext, _ t: Double) {
        for (i, pt) in [CGPoint(x: 52, y: 30), CGPoint(x: 160, y: 22), CGPoint(x: 176, y: 74)].enumerated() {
            let a = 0.5 + 0.5 * sin(t * 9 + Double(i) * 2)
            var g = c; g.opacity = a
            var star = Path(); let R = 7.0 + Double(i)
            star.move(to: CGPoint(x: pt.x, y: pt.y - R)); star.addQuadCurve(to: CGPoint(x: pt.x + R, y: pt.y), control: pt)
            star.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y + R), control: pt); star.addQuadCurve(to: CGPoint(x: pt.x - R, y: pt.y), control: pt)
            star.addQuadCurve(to: CGPoint(x: pt.x, y: pt.y - R), control: pt)
            g.fill(star, with: .color(i == 1 ? red : glow))
        }
    }
    static func drawZ(_ c: GraphicsContext, _ t: Double) {
        for i in 0..<3 {
            let p = (t * 0.55 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            var g = c; g.opacity = (1 - p) * 0.95
            g.draw(Text("z").font(.system(size: 16 + Double(i) * 5, weight: .bold, design: .rounded)).foregroundColor(.white),
                   at: CGPoint(x: 150 + p * 22 + Double(i) * 5, y: 40 - p * 36))
        }
    }
}
