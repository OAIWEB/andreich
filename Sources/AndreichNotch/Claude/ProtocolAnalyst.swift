import AppKit
import EventKit
import Foundation

/// Карточка-предложение по итогам протокола. Ничего не делается само:
/// пользователь либо принимает (галочка), либо убирает (крестик).
struct SuggestionCard: Identifiable, Equatable {
    enum Kind: String { case reminder = "напоминание", task = "задача", idea = "идея", prompt = "промт" }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let time: String          // "HH:MM" или пусто
    var session = ""          // для .prompt: название сессии Claude
    var sessionId = ""
    var prompt = ""           // готовый развёрнутый промт
    var status = ""           // "", "сохраняю…", "в Напоминаниях ✓", текст ошибки

    var icon: String {
        switch kind {
        case .reminder: return "alarm"
        case .task: return "checkmark.circle"
        case .idea: return "lightbulb"
        case .prompt: return "paperplane.fill"
        }
    }
}

/// Читает свежие строки протокола и раз в пару минут спрашивает Claude (haiku, в рамках
/// подписки), нет ли там задач, напоминаний или идей. Найденное показывает карточками.
@MainActor
final class ProtocolAnalyst: ObservableObject {
    @Published private(set) var cards: [SuggestionCard] = []
    @Published private(set) var analyzing = false
    @Published private(set) var summaryState = ""
    /// Готовая сводка дня — показывается прямо в чёлке.
    @Published private(set) var summaryText = ""
    /// Текст протокола за сегодня для вкладки «Протокол».
    @Published private(set) var protocolText = ""

    private let voice: VoiceListener
    private let claude: ClaudeMonitor
    private var timer: Timer?
    /// Промты, ждущие «ок N» в Телеграме.
    private var pending: [Int: SuggestionCard] = [:]
    private var pendingSeq = 0
    private var tgOffset = 0
    private var polling = false
    private var analyzedTotal = 0          // сколько фраз (по монотонному счётчику голоса) уже разобрано
    /// Очередь: сколько услышанных фраз ещё не разобрано.
    @Published private(set) var pendingCount = 0
    /// Когда разбор в последний раз успешно завершился.
    @Published private(set) var lastAnalysisAt: Date?
    /// Почему разбор не идёт (nil — всё нормально).
    @Published private(set) var analysisError: String?
    private var failStreak = 0
    private var nextAttempt = Date.distantPast
    private var stallAlertSent = false
    private var failAlertSent = false
    private var lastRun = Date.distantPast
    private var seenTitles: [String] = []  // что уже предлагали — чтобы не повторяться
    private let store = EKEventStore()

    private static let cli: String = {
        for c in [NSHomeDirectory() + "/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: c) { return c }
        return "claude"
    }()
    private static let minPause: TimeInterval = 90     // не дёргать модель чаще
    private static let settleAfter: TimeInterval = 8   // ждём, пока мысль закончится

    init(voice: VoiceListener, claude: ClaudeMonitor) {
        self.voice = voice
        self.claude = claude
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(); self?.eveningTick() }
        }
        startTelegramPolling()
    }

    private func tick() {
        watchAlerts()
        pendingCount = max(0, voice.totalCommitted - analyzedTotal)
        guard !analyzing, voice.state == .listening else { return }
        guard pendingCount > 0 else { return }
        let now = Date()
        guard now >= nextAttempt, now.timeIntervalSince(lastRun) > Self.minPause else { return }
        let lines = voice.lines
        guard let last = lines.last, now.timeIntervalSince(last.time) > Self.settleAfter else { return }
        // Фразы, ушедшие из памяти (больше 300 в очереди), пропускаем — они остались в файле протокола.
        let lost = max(0, pendingCount - lines.count)
        if lost > 0 { analyzedTotal += lost; pendingCount -= lost }
        let batch = min(pendingCount, 25)               // порциями: после долгого сбоя не шлём гигантский промт
        guard batch > 0 else { return }
        let start = lines.count - pendingCount          // самые старые необработанные
        analyze(Array(lines[start..<(start + batch)]))
    }

    /// Тревоги в Телеграм: распознавание глохнет или разбор не отвечает. Один раз за эпизод.
    private func watchAlerts() {
        if let since = voice.stallSince {
            if !stallAlertSent, Date().timeIntervalSince(since) > 120 {
                stallAlertSent = true
                Task { @MainActor in _ = await Self.telegramSend("⚠️ Андреич: звук идёт, а текст не записывается уже больше двух минут. Запись звука при этом сохранена в audio/ — ничего не потеряно, но карточек пока не будет.") }
            }
        } else { stallAlertSent = false }
        if failStreak >= 3 {
            if !failAlertSent {
                failAlertSent = true
                let why = analysisError ?? "нет ответа"
                Task { @MainActor in _ = await Self.telegramSend("⚠️ Андреич: разбор протокола не работает (\(why)). Фразы копятся в очереди и разберутся сами, когда связь вернётся.") }
            }
        } else if failStreak == 0 { failAlertSent = false }
    }

    private func analyze(_ fresh: [VoiceLine]) {
        analyzing = true
        lastRun = Date()
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        let body = fresh.map { "- \(clock.string(from: $0.time)) \($0.text)" }.joined(separator: "\n")
        let skip = seenTitles.suffix(12).map { "«\($0)»" }.joined(separator: ", ")
        let sessionNames = claude.sessions.prefix(8).map { "«\($0.title)»" }.joined(separator: ", ")
        let prompt = """
        Ты — Андреич, ассистент Остапа. Ниже свежий кусок протокола его устной речи \
        (распознано с микрофона, бывают ошибки распознавания). Сейчас \(clock.string(from: Date())).

        \(body)

        Выдели только то, что стоит внимания. Болтовню, ругань и проверки связи пропускай. \
        Не выдумывай ничего, чего в тексте нет. Уже предлагалось (не повторяй): \(skip.isEmpty ? "ничего" : skip).

        Виды находок:
        1. «напоминание» — конкретное дело со временем (будильник, позвонить в 10:00).
        2. «задача» — дело без привязки к проектам.
        3. «идея» — стоящая мысль.
        4. «промт» — Остап говорит о правках или новых функциях в одном из его проектов. \
        Открытые сессии Claude Code: \(sessionNames.isEmpty ? "нет" : sessionNames). \
        Если сказанное явно относится к одной из них — преврати его слова в развёрнутый \
        рабочий промт для Claude Code (конкретика: что сделать, как проверить), по-русски, \
        и укажи точное имя сессии в поле "session".

        Ответь ТОЛЬКО JSON-массивом, без пояснений и без markdown. Элемент: \
        {"type":"напоминание"|"задача"|"идея"|"промт","title":"до 6 слов","detail":"суть одним предложением","time":"HH:MM или пусто","session":"имя сессии или пусто","prompt":"готовый промт или пусто"}. \
        Максимум 3 элемента. Если ничего стоящего — [].
        """
        Task.detached(priority: .utility) {
            let out = Self.runClaude(prompt)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.analyzing = false
                guard let out else { return self.analysisFailed("Claude не ответил") }
                guard self.take(out) else { return self.analysisFailed("ответ Claude не разобрать") }
                self.analyzedTotal += fresh.count        // успех: порция прошла
                self.failStreak = 0
                self.analysisError = nil
                self.lastAnalysisAt = Date()
                self.pendingCount = max(0, self.voice.totalCommitted - self.analyzedTotal)
            }
        }
    }

    /// Порция не разобрана: она остаётся в очереди, следующая попытка — с растущей паузой (до 10 минут).
    private func analysisFailed(_ why: String) {
        failStreak += 1
        analysisError = "\(why) (\(failStreak))"
        let pause = min(600.0, Self.minPause * pow(2.0, Double(failStreak)))
        nextAttempt = Date().addingTimeInterval(pause)
        VoiceLog.write("разбор не удался: \(why); попытка \(failStreak), следующая через \(Int(pause)) с")
    }

    @discardableResult
    private func take(_ out: String) -> Bool {
        guard let open = out.firstIndex(of: "["), let close = out.lastIndex(of: "]"), open < close,
              let data = String(out[open...close]).data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        for item in raw.prefix(3) {
            guard let title = item["title"] as? String, !title.isEmpty else { continue }
            let lowered = title.lowercased()
            guard !seenTitles.contains(where: { $0.lowercased() == lowered }) else { continue }
            let kind = SuggestionCard.Kind(rawValue: (item["type"] as? String ?? "идея")) ?? .idea
            seenTitles.append(title)
            var card = SuggestionCard(kind: kind, title: title,
                                      detail: item["detail"] as? String ?? "",
                                      time: item["time"] as? String ?? "")
            if kind == .prompt {
                card.session = item["session"] as? String ?? ""
                card.prompt = item["prompt"] as? String ?? ""
                if let match = claude.sessions.first(where: { $0.title.lowercased() == card.session.lowercased() })
                    ?? claude.sessions.first(where: { $0.title.lowercased().contains(card.session.lowercased()) && !card.session.isEmpty }) {
                    card.sessionId = match.id
                    card.session = match.title
                }
                guard !card.prompt.isEmpty, !card.sessionId.isEmpty else { continue }
                offerPromptInTelegram(card)
            }
            cards.append(card)
        }
        if cards.count > 4 { cards.removeFirst(cards.count - 4) }
        return true
    }

    // MARK: действия по карточке
    func dismiss(_ card: SuggestionCard) { cards.removeAll { $0.id == card.id } }

    func accept(_ card: SuggestionCard) {
        if card.kind == .prompt { runPrompt(card); return }
        setStatus(card, "сохраняю…")
        Task { @MainActor in
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = (try? await store.requestFullAccessToReminders()) ?? false
            } else {
                granted = false
            }
            guard granted else {
                setStatus(card, "нет доступа к Напоминаниям — разрешите в Настройках")
                return
            }
            let r = EKReminder(eventStore: store)
            r.title = card.title
            r.notes = card.detail + "\n\nИз протокола Андреича"
            r.calendar = store.defaultCalendarForNewReminders()
            if let due = Self.todayAt(card.time) {
                r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                r.addAlarm(EKAlarm(absoluteDate: due))
            }
            do {
                try store.save(r, commit: true)
                setStatus(card, "в Напоминаниях ✓")
                let id = card.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.cards.removeAll { $0.id == id }
                }
            } catch {
                setStatus(card, "не сохранилось: \(error.localizedDescription)")
            }
        }
    }

    private func setStatus(_ card: SuggestionCard, _ s: String) {
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[i].status = s
    }

    private static func todayAt(_ hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var d = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())!
        if d < Date() { d = Calendar.current.date(byAdding: .day, value: 1, to: d)! }
        return d
    }

    /// Перечитать протокол и сохранённую сводку за выбранный день (0 — сегодня, 1 — вчера…).
    func reloadProtocol(daysAgo: Int = 0) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let key = day.string(from: date)
        protocolText = (try? String(contentsOf: ProtocolWriter.directory.appendingPathComponent("\(key).md"), encoding: .utf8)) ?? ""
        if let saved = try? String(contentsOf: ProtocolWriter.directory.appendingPathComponent("\(key)-сводка.md"), encoding: .utf8) {
            summaryText = saved
        } else if daysAgo != 0 {
            summaryText = ""
        }
    }

    /// Есть ли вообще записи за тот день (чтобы не листать в пустоту бесконечно).
    func hasProtocol(daysAgo: Int) -> Bool {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        return FileManager.default.fileExists(
            atPath: ProtocolWriter.directory.appendingPathComponent("\(day.string(from: date)).md").path)
    }

    func openProtocolFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ProtocolWriter.directory])
    }

    // MARK: сводка дня
    func makeDailySummary() {
        guard summaryState != "думаю…" else { return }
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let file = ProtocolWriter.directory.appendingPathComponent("\(day.string(from: Date())).md")
        guard let text = try? String(contentsOf: file, encoding: .utf8), text.count > 80 else {
            summaryState = "протокол пока пуст"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.summaryState = "" }
            return
        }
        summaryState = "думаю…"
        let prompt = """
        Ниже протокол устной речи Остапа за день (распознано с микрофона, бывают ошибки). \
        Напиши по-русски короткую сводку в markdown: «## О чём говорили» (3–6 пунктов), \
        «## Решено и сделано», «## Повисло» (задачи и вопросы без ответа). Пиши только то, \
        что есть в тексте, без фантазий. Без вступлений.

        \(String(text.suffix(24_000)))
        """
        Task.detached(priority: .utility) {
            let out = Self.runClaude(prompt)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let out, !out.isEmpty else { self.summaryState = "не вышло, попробуйте ещё раз"; return }
                let target = ProtocolWriter.directory.appendingPathComponent("\(day.string(from: Date()))-сводка.md")
                let head = "# Сводка дня · \(day.string(from: Date()))\n\n"
                try? (head + out + "\n").write(to: target, atomically: true, encoding: .utf8)
                self.summaryState = ""
                self.summaryText = out
            }
        }
    }

    // MARK: отправка в Телеграм (бот @oaiwebandrbot — тот же Андреич)
    @Published private(set) var tgState = ""

    private static func telegramConfig() -> (token: String, chat: String)? {
        let f = VoiceLog.support.appendingPathComponent("telegram.env")
        guard let text = try? String(contentsOf: f, encoding: .utf8) else { return nil }
        var token = "", chat = ""
        for line in text.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[0] == "TG_BOT_TOKEN" { token = kv[1].trimmingCharacters(in: .whitespaces) }
            if kv[0] == "TG_CHAT_ID" { chat = kv[1].trimmingCharacters(in: .whitespaces) }
        }
        return token.isEmpty || chat.isEmpty ? nil : (token, chat)
    }

    /// Шлёт текст в личку Остапа. Возвращает понятный статус.
    private static func telegramSend(_ text: String) async -> String {
        guard let cfg = telegramConfig() else { return "нет токена (telegram.env)" }
        guard var comps = URLComponents(string: "https://api.telegram.org/bot\(cfg.token)/sendMessage") else { return "кривой адрес" }
        _ = comps
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["chat_id": cfg.chat, "text": String(text.prefix(4000)), "disable_web_page_preview": true]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { return "ок" }
            let desc = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["description"] as? String
            return "Телеграм отказал: \(desc ?? "без причины")"
        } catch { return "сеть: \(error.localizedDescription)" }
    }

    /// Кнопка «в Телегу»: отправляет готовую сводку дня.
    func sendSummaryToTelegram() {
        guard !summaryText.isEmpty else { tgState = "сначала соберите сводку"; return }
        tgState = "отправляю…"
        let title = DateFormatter(); title.dateFormat = "d MMMM"; title.locale = Locale(identifier: "ru_RU")
        let text = "Сводка дня · \(title.string(from: Date()))\n\n" + summaryText
            .replacingOccurrences(of: "## ", with: "— ")
            .replacingOccurrences(of: "**", with: "")
        Task { @MainActor in
            let r = await Self.telegramSend(text)
            tgState = r == "ок" ? "улетело в Телегу ✓" : r
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.tgState = "" }
        }
    }

    /// Вечером, в 21:30, если за день были записи — сводка собирается и уходит в Телегу сама.
    private func eveningTick() {
        let now = Date()
        let cal = Calendar.current
        guard cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now) >= 21 * 60 + 30 else { return }
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        let key = day.string(from: now)
        guard UserDefaults.standard.string(forKey: "tgSummarySent") != key else { return }
        let file = ProtocolWriter.directory.appendingPathComponent("\(key).md")
        guard let text = try? String(contentsOf: file, encoding: .utf8), text.count > 200 else { return }
        UserDefaults.standard.set(key, forKey: "tgSummarySent")
        makeDailySummary()
        Task { @MainActor in
            for _ in 0..<60 where summaryText.isEmpty || summaryState == "думаю…" {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            if !summaryText.isEmpty { sendSummaryToTelegram() }
        }
    }

    // MARK: промты в сессии Claude — подтверждение в Телеграме и запуск
    private func offerPromptInTelegram(_ card: SuggestionCard) {
        pendingSeq += 1
        let n = pendingSeq
        pending[n] = card
        let text = """
        Андреич услышал задачу для сессии «\(card.session)»:

        \(card.prompt)

        Ответь «ок \(n)» — отправлю в работу. «нет \(n)» — забуду.
        """
        Task { @MainActor in _ = await Self.telegramSend(text) }
    }

    /// Запустить промт в сессии Claude Code (продолжение сессии из командной строки).
    func runPrompt(_ card: SuggestionCard) {
        guard !card.sessionId.isEmpty, !card.prompt.isEmpty else { return }
        setStatus(card, "отправил в «\(card.session)»…")
        VoiceLog.write("промт в сессию «\(card.session)» (\(card.sessionId))")
        let cwd = claude.cwd(for: card.sessionId) ?? NSHomeDirectory()
        let sessionId = card.sessionId, promptText = card.prompt, title = card.session
        let cardId = card.id
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.cli)
            p.arguments = ["--resume", sessionId, "-p", promptText]
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch {
                await MainActor.run { [weak self] in self?.cardStatus(cardId, "не запустилось: \(error.localizedDescription)") }
                return
            }
            let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1800, execute: killer)
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            killer.cancel()
            let ok = p.terminationStatus == 0
            await MainActor.run { [weak self] in
                self?.cardStatus(cardId, ok ? "сделано ✓" : "упало, код \(p.terminationStatus)")
            }
            _ = await Self.telegramSend(ok ? "«\(title)»: задача выполнена ✓" : "«\(title)»: не получилось, загляни в сессию")
        }
    }

    private func cardStatus(_ id: UUID, _ st: String) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].status = st
    }

    /// Слушаем ответы «ок N»/«нет N» в Телеграме (длинный опрос).
    private func startTelegramPolling() {
        guard !polling, Self.telegramConfig() != nil else { return }
        polling = true
        Task { @MainActor [weak self] in
            while let self, self.polling {
                await self.pollTelegramOnce()
            }
        }
    }

    private func pollTelegramOnce() async {
        guard let cfg = Self.telegramConfig(),
              let url = URL(string: "https://api.telegram.org/bot\(cfg.token)/getUpdates?timeout=25&offset=\(tgOffset)") else {
            try? await Task.sleep(nanoseconds: 60_000_000_000); return
        }
        do {
            var req = URLRequest(url: url); req.timeoutInterval = 40
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  j["ok"] as? Bool == true, let updates = j["result"] as? [[String: Any]] else {
                if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (j["error_code"] as? Int) == 409 {
                    VoiceLog.write("Телеграм: бота уже слушает кто-то другой (409) — подтверждения «ок N» работать не будут")
                    polling = false
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000); return
            }
            for u in updates {
                if let id = u["update_id"] as? Int { tgOffset = max(tgOffset, id + 1) }
                guard let msg = u["message"] as? [String: Any],
                      let chat = msg["chat"] as? [String: Any],
                      "\(chat["id"] ?? "")" == cfg.chat,
                      let text = (msg["text"] as? String)?.lowercased().trimmingCharacters(in: .whitespaces) else { continue }
                let parts = text.split(separator: " ").map(String.init)
                guard parts.count == 2, let n = Int(parts[1]), let card = pending[n] else { continue }
                if ["ок", "ok", "да", "давай"].contains(parts[0]) {
                    pending[n] = nil
                    runPrompt(card)
                    _ = await Self.telegramSend("Принял, отправил в «\(card.session)». Как закончит — напишу.")
                } else if ["нет", "no", "отмена"].contains(parts[0]) {
                    pending[n] = nil
                    dismiss(card)
                    _ = await Self.telegramSend("Ок, забыл.")
                }
            }
        } catch {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }

    // MARK: вызов Claude
    private nonisolated static func runClaude(_ prompt: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli)
        p.arguments = ["-p", "--model", "haiku", prompt]
        p.currentDirectoryURL = VoiceLog.support
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
