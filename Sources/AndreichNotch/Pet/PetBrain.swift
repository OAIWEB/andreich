import AppKit
import SwiftUI

enum PetMode { case home, dropping, roaming, returning, entering }

/// Поведение Андреича: живёт в чёлке, выпадает оттуда гулять по низу экрана,
/// возвращается по стене и потолку (под меню-баром), реагирует на работу Claude.
@MainActor
final class PetBrain: ObservableObject {
    @Published private(set) var mode: PetMode = .home
    @Published private(set) var pose: PetPose = .sleep
    @Published private(set) var facing: CGFloat = 1
    @Published private(set) var rotation: Double = 0
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var bubble: String?
    @Published var claudeWorking = false
    @Published var listening = false          // микрофон включён: Андреич внимательно слушает

    /// Центр спрайта в экранных координатах AppKit (не @Published: окно двигается напрямую).
    private(set) var position: CGPoint = .zero
    var geometry: NotchGeometry

    var footOffset: CGFloat = 39
    private var vy: CGFloat = 0
    private var bounces = 0
    private var dropT: Double = 0
    private var cheerOnLanding = false

    private enum ActKind { case walk, idle, sit, wave, cheer }
    private var act: ActKind = .idle
    private var actEnds = Date()
    private var walkTarget: CGFloat = 0
    private var roamEnds = Date()

    private struct Waypoint { var foot: CGPoint; var rotation: Double; var speed: CGFloat }
    private var waypoints: [Waypoint] = []
    private var wpIndex = 0
    private var segStart = CGPoint.zero
    private var segProgress: CGFloat = 0
    private var wallSide: CGFloat = 1

    private var enterT: Double = 0
    private var enterFrom = CGPoint.zero

    private var bubbleEnds = Date.distantPast
    private var nextWander = Date().addingTimeInterval(.random(in: 90...240))

    init(geometry: NotchGeometry) {
        self.geometry = geometry
        self.position = homeCenter
    }

    // MARK: геометрия
    var floorFootY: CGFloat { geometry.visibleFrame.minY + 2 }
    var ceilFootY: CGFloat { geometry.visibleFrame.maxY }
    var homeCenter: CGPoint {
        CGPoint(x: geometry.notchRect.maxX + NotchViewModel.wing / 2,
                y: geometry.screenFrame.maxY - geometry.notchSize.height / 2)
    }
    var homePose: PetPose { listening ? .listen : (claudeWorking ? .work : .sleep) }

    // MARK: команды
    func goForWalk() {
        guard mode == .home else { return }
        cheerOnLanding = false
        startDrop()
    }

    func sendHome() {
        if mode == .roaming { startReturning() }
    }

    func poke() {
        if mode == .roaming { act = .cheer; actEnds = Date().addingTimeInterval(0.9) }
        say(["Чего?", "Слушаю!", "Работаем!", "Я тут", "Опять правки?", "Эй!"].randomElement()!, 2.5)
    }

    /// Claude закончил всю работу. Пока занят — сидим смирно.
    func celebrate() {
        guard !claudeWorking else { return }
        let now = Date()
        switch mode {
        case .home:
            cheerOnLanding = true
            startDrop()
        case .roaming:
            act = .cheer; actEnds = now.addingTimeInterval(3.5)
            roamEnds = max(roamEnds, now.addingTimeInterval(8))
            say("Готово!", 3)
        default: break
        }
    }

    // MARK: тик
    func tick(_ dt: TimeInterval) {
        let now = Date()
        switch mode {
        case .home:
            setPose(homePose); setScale(1); setRotation(0)
            position = homeCenter
            // Сам по экрану не шатается: выход — только «работа закончена» или кнопка в меню.

        case .dropping:
            dropT += dt
            setScale(min(1, 0.3 + CGFloat(dropT) * 3))
            setPose(.idle)
            vy += 2200 * CGFloat(dt)
            position.y -= vy * CGFloat(dt)
            let ground = floorFootY + footOffset
            if position.y <= ground {
                position.y = ground
                if bounces == 0 { vy = -vy * 0.3; bounces = 1 } else { land(now) }
            }

        case .roaming:
            setScale(1); setRotation(0)
            position.y = floorFootY + footOffset
            let f = geometry.screenFrame
            position.x = min(max(position.x, f.minX + 50), f.maxX - 50)
            switch act {
            case .walk:
                setPose(.walk)
                let dir: CGFloat = walkTarget > position.x ? 1 : -1
                position.x += dir * 75 * CGFloat(dt)
                setFacing(dir)
                if abs(walkTarget - position.x) < 3 { pickNextAct(now) }
            case .idle: setPose(.idle); if now >= actEnds { pickNextAct(now) }
            case .sit: setPose(.sit); if now >= actEnds { pickNextAct(now) }
            case .wave: setPose(.wave); if now >= actEnds { pickNextAct(now) }
            case .cheer: setPose(.cheer); if now >= actEnds { pickNextAct(now) }
            }
            if now >= roamEnds, act != .cheer { startReturning() }

        case .returning:
            followPath(dt)

        case .entering:
            enterT += dt / 0.4
            let k = CGFloat(min(1, enterT))
            let e = k * k
            position = CGPoint(x: enterFrom.x + (homeCenter.x - enterFrom.x) * e,
                               y: enterFrom.y + (homeCenter.y - enterFrom.y) * e)
            setScale(1 - 0.7 * k)
            if enterT >= 1 {
                mode = .home
                nextWander = now.addingTimeInterval(.random(in: 150...420))
            }
        }
        if bubble != nil, now >= bubbleEnds { bubble = nil }
    }

    // MARK: внутреннее
    private func startDrop() {
        position = homeCenter
        vy = 0; bounces = 0; dropT = 0
        setRotation(0); setScale(0.3)
        mode = .dropping
    }

    private func land(_ now: Date) {
        mode = .roaming
        if cheerOnLanding {   // короткая вылазка: порадовался — и сразу домой
            act = .cheer; actEnds = now.addingTimeInterval(3.5)
            roamEnds = now.addingTimeInterval(7)
            say("Готово!", 3)
            cheerOnLanding = false
        } else {
            roamEnds = now.addingTimeInterval(.random(in: 25...45))
            pickNextAct(now)
        }
    }

    private func pickNextAct(_ now: Date) {
        let f = geometry.screenFrame
        switch Double.random(in: 0..<1) {
        case ..<0.5:
            act = .walk
            walkTarget = CGFloat.random(in: (f.minX + 90)...(f.maxX - 90))
        case ..<0.75: act = .idle; actEnds = now.addingTimeInterval(.random(in: 2...5))
        case ..<0.9: act = .sit; actEnds = now.addingTimeInterval(.random(in: 3...6))
        default: act = .wave; actEnds = now.addingTimeInterval(.random(in: 1.5...2.5))
        }
    }

    private func startReturning() {
        let f = geometry.screenFrame
        let nearLeft = position.x < f.midX
        let wallX = nearLeft ? f.minX + 2 : f.maxX - 2
        wallSide = nearLeft ? 1 : -1
        waypoints = [
            Waypoint(foot: CGPoint(x: wallX, y: floorFootY), rotation: 0, speed: 90),
            Waypoint(foot: CGPoint(x: wallX, y: ceilFootY), rotation: nearLeft ? 90 : -90, speed: 80),
            Waypoint(foot: CGPoint(x: homeCenter.x, y: ceilFootY), rotation: 180, speed: 100),
        ]
        wpIndex = 0
        segStart = CGPoint(x: position.x, y: floorFootY)
        segProgress = 0
        mode = .returning
    }

    private func followPath(_ dt: TimeInterval) {
        guard wpIndex < waypoints.count else { startEntering(); return }
        let wp = waypoints[wpIndex]
        let dx = wp.foot.x - segStart.x, dy = wp.foot.y - segStart.y
        let len = max(1, hypot(dx, dy))
        segProgress += wp.speed * CGFloat(dt) / len
        if segProgress >= 1 {
            segStart = wp.foot; wpIndex += 1; segProgress = 0
            if wpIndex >= waypoints.count { startEntering(); return }
        }
        let cur = waypoints[wpIndex]
        let cdx = cur.foot.x - segStart.x
        let t = min(1, segProgress)
        let foot = CGPoint(x: segStart.x + (cur.foot.x - segStart.x) * t,
                           y: segStart.y + (cur.foot.y - segStart.y) * t)
        // плавный поворот к ориентации текущего отрезка
        let target = cur.rotation
        setRotation(rotation + (target - rotation) * min(1, dt * 9))
        switch wpIndex {
        case 0: setFacing(cdx >= 0 ? 1 : -1)
        case 1: setFacing(wallSide > 0 ? -1 : 1)
        default: setFacing(cdx > 0 ? -1 : 1)
        }
        setPose(.walk); setScale(1)
        let rad = rotation * .pi / 180
        position = CGPoint(x: foot.x + CGFloat(sin(rad)) * footOffset,
                           y: foot.y + CGFloat(cos(rad)) * footOffset)
    }

    private func startEntering() {
        enterFrom = position; enterT = 0
        mode = .entering
    }

    private func say(_ text: String, _ seconds: TimeInterval) { bubble = text; bubbleEnds = Date().addingTimeInterval(seconds) }
    private func setPose(_ p: PetPose) { if pose != p { pose = p } }
    private func setFacing(_ f: CGFloat) { if facing != f { facing = f } }
    private func setScale(_ v: CGFloat) { if abs(scale - v) > 0.002 { scale = v } }
    private func setRotation(_ r: Double) { if abs(rotation - r) > 0.05 { rotation = r } }
}
