import Foundation

struct ClaudeSession: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var lastActivity: Date
}

/// Следит за сессиями Claude Code без хуков и без правки настроек:
/// смотрит, как свежо обновляются файлы переписок в ~/.claude/projects
/// (и берёт названия сессий из десктопного приложения Claude).
@MainActor
final class ClaudeMonitor: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var isWorking = false
    var onTaskFinished: (() -> Void)?

    /// Сколько секунд после последней записи в переписку считаем, что Claude работает.
    static let workWindow: TimeInterval = 18

    private var titles: [String: String] = [:]
    private var titlesLoadedAt = Date.distantPast
    private var candidates: [String] = []      // файлы, менявшиеся за последние 6 часов
    private var cwdCache: [String: String] = [:]
    private var scanning = false
    private var workStart: Date?
    private var workLatest = Date.distantPast

    struct ScanResult: Sendable {
        var sessions: [ClaudeSession]
        var titles: [String: String]
        var cwd: [String: String]
        var candidates: [String]
    }

    /// Рабочая папка сессии — нужна, чтобы продолжить её из командной строки.
    func cwd(for id: String) -> String? { cwdCache[id] }

    func poll() {
        guard !scanning else { return }
        scanning = true
        let reload = Date().timeIntervalSince(titlesLoadedAt) > 25 || candidates.isEmpty
        let knownTitles = titles, knownCwd = cwdCache, known = candidates
        Task.detached(priority: .utility) { [weak self] in
            let r = ClaudeMonitor.scan(titles: knownTitles, cwd: knownCwd, reloadTitles: reload, candidates: known)
            await MainActor.run { self?.apply(r, reloaded: reload) }
        }
    }

    private func apply(_ r: ScanResult, reloaded: Bool) {
        scanning = false
        titles = r.titles
        cwdCache = r.cwd
        candidates = r.candidates
        if reloaded { titlesLoadedAt = Date() }
        if sessions != r.sessions { sessions = r.sessions }

        let now = Date()
        let latest = r.sessions.first?.lastActivity ?? .distantPast
        let working = now.timeIntervalSince(latest) < Self.workWindow
        if working {
            if !isWorking { workStart = latest }
            workLatest = latest
        } else if isWorking {
            if let start = workStart, workLatest.timeIntervalSince(start) > 8 { onTaskFinished?() }
            workStart = nil
        }
        if working != isWorking { isWorking = working }
    }

    nonisolated static func scan(titles: [String: String], cwd: [String: String], reloadTitles: Bool, candidates: [String]) -> ScanResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var titles = titles
        var cwdCache = cwd

        if reloadTitles {
            let base = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
            for account in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] {
                for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                    for f in (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? []
                    where f.lastPathComponent.hasPrefix("local_") && f.pathExtension == "json" {
                        // файлы сессий огромные (списки инструментов), а id и название лежат в самом начале:
                        // читаем первые 4 КБ вместо разбора всего JSON
                        guard let h = try? FileHandle(forReadingFrom: f) else { continue }
                        let head = (try? h.read(upToCount: 4096)) ?? Data()
                        try? h.close()
                        guard let text = String(data: head, encoding: .utf8),
                              let cid = jsonField("cliSessionId", in: text),
                              let t = jsonField("title", in: text) else { continue }
                        titles[cid] = t
                    }
                }
            }
        }

        let cutoff = Date().addingTimeInterval(-6 * 3600)
        var files: [URL] = []
        if reloadTitles {
            // полный обход всех проектов: редко (раз в ~25 с)
            let root = home.appendingPathComponent(".claude/projects")
            for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                files += ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "jsonl" }
            }
        } else {
            files = candidates.map { URL(fileURLWithPath: $0) }
        }
        var found: [ClaudeSession] = []
        var newCandidates: [String] = []
        for f in files {
            guard let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  m > cutoff else { continue }
            newCandidates.append(f.path)
            let sid = f.deletingPathExtension().lastPathComponent
            var title = titles[sid]
            if title == nil {
                if let cached = cwdCache[f.path] { title = cached }
                else if let name = projectName(of: f) { cwdCache[f.path] = name; title = name }
            }
            found.append(ClaudeSession(id: f.path, title: title ?? String(sid.prefix(8)), lastActivity: m))
        }
        found.sort { $0.lastActivity > $1.lastActivity }
        return ScanResult(sessions: Array(found.prefix(6)), titles: titles, cwd: cwdCache, candidates: reloadTitles ? newCandidates : candidates)
    }

    /// Строковое поле верхнего уровня из начала JSON (с разбором \\uXXXX и экранирования).
    nonisolated private static func jsonField(_ key: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "\"\(key)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")"),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text),
              let d = "[\(text[r])]".data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [String] else { return nil }
        return arr.first
    }

    /// Папка проекта из первых килобайт переписки (поле "cwd").
    nonisolated private static func projectName(of file: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 16_384), let text = String(data: data, encoding: .utf8) else { return nil }
        guard let re = try? NSRegularExpression(pattern: "\"cwd\":\"([^\"]+)\""),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return (String(text[r]) as NSString).lastPathComponent
    }
}
