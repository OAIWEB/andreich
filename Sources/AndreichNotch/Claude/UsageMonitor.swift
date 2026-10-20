import Foundation
import SwiftUI

/// Лимиты подписки Claude: сколько осталось от недельных и сколько можно потратить сегодня.
/// Счёт ведёт scripts/usage.py (лежит в Resources) — он же держит кэш и дневной учёт.
struct UsageState: Codable, Equatable {
    var weeklyUsed: Double
    var weeklyLeft: Double
    var weekResetsIn: String
    var fiveHourUsed: Double
    var fiveHourResetsIn: String
    var dayBudget: Double
    var daySpent: Double
    var dayLeft: Double
    var dayFill: Double
    var daysLeft: Int
    var reserve: Double
    var state: String        // ok / warn / over
    var stale: Bool

    enum CodingKeys: String, CodingKey {
        case weeklyUsed = "weekly_used", weeklyLeft = "weekly_left", weekResetsIn = "week_resets_in"
        case fiveHourUsed = "five_hour_used", fiveHourResetsIn = "five_hour_resets_in"
        case dayBudget = "day_budget", daySpent = "day_spent", dayLeft = "day_left", dayFill = "day_fill"
        case daysLeft = "days_left", reserve, state, stale
    }

    var color: Color {
        switch state {
        case "over": return Color(red: 0.95, green: 0.27, blue: 0.27)
        case "warn": return Color(red: 0.98, green: 0.76, blue: 0.25)
        default: return tiffany
        }
    }
    /// Короткая подпись о дневной норме.
    var dayCaption: String {
        if state == "over" { return String(format: "сегодня перебор на %.1f%%", -dayLeft) }
        return String(format: "сегодня можно ещё %.1f%%", max(0, dayLeft))
    }
    /// Пояснение, откуда взялась норма.
    var dayExplain: String {
        String(format: "норма на день %.1f%% = остаток %.0f%% на %d дн., %.0f%% на вс",
               dayBudget, weeklyLeft, daysLeft, reserve)
    }
}

@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var usage: UsageState?
    @Published private(set) var failure: String?

    private var timer: Timer?
    private var busy = false
    private let script: URL?

    init() {
        script = Bundle.main.url(forResource: "usage", withExtension: "py")
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Проекты/Андреич-чёлка/scripts/usage.py")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let script, !busy else { return }
        busy = true
        Task.detached(priority: .utility) {
            let out = Self.run(script)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busy = false
                if let out, let data = out.data(using: .utf8),
                   let s = try? JSONDecoder().decode(UsageState.self, from: data) {
                    self.usage = s
                    self.failure = nil
                } else if self.usage == nil {
                    self.failure = "нет доступа к лимитам"
                }
            }
        }
    }

    private nonisolated static func run(_ script: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [script.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
