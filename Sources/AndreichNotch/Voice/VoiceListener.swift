import AVFoundation
import Speech

struct VoiceLine: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let text: String
}

/// Потокобезопасная «коробка» для текущего запроса: звук приходит из аудио-потока.
final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock(); defer { lock.unlock() }
        let old = request; request = r; return old
    }
    func append(_ b: AVAudioPCMBuffer) { lock.lock(); request?.append(b); lock.unlock() }
}

/// Пишет звук на диск и меряет уровень — чтобы отличать тишину от сломавшегося распознавания.
/// Живёт в аудио-потоке, поэтому всё под замком.
final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var lastLoud = Date.distantPast
    private(set) var writeError: String?

    func open(_ url: URL, format: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 48_000,
        ]
        do { file = try AVAudioFile(forWriting: url, settings: settings) }
        catch { file = nil; writeError = error.localizedDescription }
    }
    func close() { lock.lock(); file = nil; lock.unlock() }

    func write(_ b: AVAudioPCMBuffer) {
        // уровень сигнала
        if let ch = b.floatChannelData {
            let n = Int(b.frameLength)
            var sum: Float = 0
            for i in 0..<n { let v = ch[0][i]; sum += v * v }
            if n > 0, (sum / Float(n)).squareRoot() > 0.012 { lastLoud = Date() }
        }
        lock.lock(); defer { lock.unlock() }
        guard let file else { return }
        do { try file.write(from: b) } catch { writeError = error.localizedDescription; self.file = nil }
    }
    var lastLoudAt: Date { lastLoud }
}

/// Слушает микрофон, пока он включён. Речь распознаётся прямо на Маке, а сам звук
/// параллельно пишется в файл — если распознавание споткнётся, запись останется.
/// Протокол дня: ~/Library/Application Support/AndreichNotch/protocol/ГГГГ-ММ-ДД.md
/// Звук: ~/Library/Application Support/AndreichNotch/audio/ГГГГ-ММ-ДД_ЧЧ-ММ-СС.m4a
@MainActor
final class VoiceListener: ObservableObject {
    enum State: Equatable { case off, starting, listening, blocked(String) }

    @Published private(set) var state: State = .off
    @Published private(set) var partial = ""
    @Published private(set) var lines: [VoiceLine] = []
    /// Куда пишется звук текущей сессии (для подписи в панели).
    @Published private(set) var audioName = ""

    var isOn: Bool { state == .listening || state == .starting }

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private let box = RequestBox()
    private let sink = AudioSink()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var lastChange = Date()
    private var lastResult = Date()
    private var requestStarted = Date()
    private var watchdog: Timer?
    private var errorTimes: [Date] = []
    private var deadRestarts = 0
    private static let wasOnKey = "micWasOn"

    /// Если микрофон был включён, когда приложение закрылось (или его перезапустили) — поднимаем снова.
    func restoreIfWasOn() {
        guard UserDefaults.standard.bool(forKey: Self.wasOnKey) else { return }
        VoiceLog.write("микрофон был включён до перезапуска — включаю снова")
        start(restored: true)
    }

    func toggle() { isOn ? stop() : start() }

    func start(restored: Bool = false) {
        guard !isOn else { return }
        state = .starting
        Task { @MainActor in
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
            guard mic else { fail("Нет доступа к микрофону. Разрешите: Настройки → Конфиденциальность → Микрофон"); return }
            guard speech == .authorized else { fail("Нет доступа к распознаванию речи. Разрешите в Настройки → Конфиденциальность"); return }
            guard let r = recognizer, r.isAvailable, r.supportsOnDeviceRecognition else {
                fail("Русское распознавание на устройстве недоступно. Включите диктовку на русском в Настройки → Клавиатура"); return
            }
            guard startEngine() else { return }
            state = .listening
            UserDefaults.standard.set(true, forKey: Self.wasOnKey)
            errorTimes = []; deadRestarts = 0
            beginRequest()
            VoiceLog.write("микрофон включён, звук пишется в \(audioName)")
            ProtocolWriter.note(restored ? "микрофон включён снова после перезапуска, звук: \(audioName)"
                                         : "микрофон включён, звук: \(audioName)")
            watchdog?.invalidate()
            watchdog = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.watch() }
            }
        }
    }

    /// byUser=false — приложение закрывается само: запись останавливаем, но помним,
    /// что микрофон был включён, и поднимем его после перезапуска.
    func stop(byUser: Bool = true) {
        guard isOn else { return }
        watchdog?.invalidate(); watchdog = nil
        commitPartial()
        generation += 1
        _ = box.set(nil)
        task?.cancel(); task = nil
        stopEngine()
        partial = ""
        state = .off
        if byUser { UserDefaults.standard.set(false, forKey: Self.wasOnKey) }
        VoiceLog.write(byUser ? "микрофон выключен" : "приложение закрывается, запись прервана")
        ProtocolWriter.note(byUser ? "микрофон выключен" : "приложение закрылось, запись прервана")
    }

    private func fail(_ message: String) {
        state = .blocked(message)
        UserDefaults.standard.set(false, forKey: Self.wasOnKey)
        VoiceLog.write("не удалось начать: \(message)")
        ProtocolWriter.note("запись не началась: \(message)")
    }

    // MARK: звук
    @discardableResult
    private func startEngine() -> Bool {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { fail("Микрофон не отдаёт звук (частота 0). Проверьте вход в Настройках звука"); return false }
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = VoiceLog.audioDirectory.appendingPathComponent("\(stamp.string(from: Date())).m4a")
        try? FileManager.default.createDirectory(at: VoiceLog.audioDirectory, withIntermediateDirectories: true)
        sink.open(url, format: format)
        audioName = url.lastPathComponent
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [box, sink] buffer, _ in
            box.append(buffer)
            sink.write(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0); sink.close()
            fail("Микрофон не запустился: \(error.localizedDescription)")
            return false
        }
        if let e = sink.writeError { VoiceLog.write("звук не пишется в файл: \(e)") }
        return true
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        sink.close()
    }

    /// Полная пересборка цепочки, когда распознавание или движок умерли молча.
    private func restartEngine(reason: String) {
        VoiceLog.write("перезапускаю запись: \(reason)")
        ProtocolWriter.note("запись перезапущена (\(reason))")
        generation += 1
        _ = box.set(nil)
        task?.cancel(); task = nil
        stopEngine()
        guard startEngine() else { return }
        beginRequest()
    }

    // MARK: распознавание
    private func beginRequest() {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.addsPunctuation = true
        generation += 1
        let gen = generation
        let old = box.set(req)
        old?.endAudio()
        task?.cancel()                 // старую задачу обязательно снимаем, иначе новые перестают запускаться
        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            let message = error?.localizedDescription
            Task { @MainActor in self?.handle(text: text, final: final, failed: failed, message: message, gen: gen) }
        }
        requestStarted = Date()
        lastChange = Date()
        lastResult = Date()
    }

    private func handle(text: String?, final: Bool, failed: Bool, message: String?, gen: Int) {
        guard gen == generation, isOn else { return }
        lastResult = Date()
        if let text, text != partial { partial = text; lastChange = Date() }
        if final || failed {
            commitPartial()
            if failed {
                VoiceLog.write("ошибка распознавания: \(message ?? "неизвестно")")
                let now = Date()
                errorTimes = errorTimes.filter { now.timeIntervalSince($0) < 10 } + [now]
                if errorTimes.count > 6 {
                    restartEngine(reason: "распознавание сбоит подряд")
                    errorTimes = []
                    return
                }
            }
            beginRequest()
        }
    }

    /// Фраза считается законченной, когда текст не меняется 1,6 с; плюс страховка от лимита в минуту
    /// и сторож на случай, когда звук идёт, а распознавание молчит.
    private func watch() {
        guard state == .listening else { return }
        let now = Date()
        if !engine.isRunning { restartEngine(reason: "движок звука остановился"); return }
        if !partial.isEmpty, now.timeIntervalSince(lastChange) > 1.6 { commitPartial(); beginRequest(); return }
        if now.timeIntervalSince(requestStarted) > 50 { commitPartial(); beginRequest(); return }
        // звук есть, а результатов нет дольше 15 секунд — значит задача умерла молча
        if partial.isEmpty, now.timeIntervalSince(sink.lastLoudAt) < 3, now.timeIntervalSince(lastResult) > 15 {
            deadRestarts += 1
            if deadRestarts >= 3 { deadRestarts = 0; restartEngine(reason: "распознавание молчит при живом звуке") }
            else { VoiceLog.write("распознавание молчит при живом звуке — новый запрос"); beginRequest() }
        }
    }

    private func commitPartial() {
        let t = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        guard !t.isEmpty else { return }
        let line = VoiceLine(time: Date(), text: t)
        lines.append(line)
        if lines.count > 60 { lines.removeFirst(lines.count - 60) }
        ProtocolWriter.append(line)
    }
}

/// Служебный журнал записи — чтобы потом было видно, что происходило с микрофоном.
enum VoiceLog {
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AndreichNotch")
    }
    static var audioDirectory: URL { support.appendingPathComponent("audio") }

    static func write(_ text: String) {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let f = support.appendingPathComponent("voice.log")
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(stamp.string(from: Date()))  \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: f) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: data) }
        else { try? data.write(to: f) }
    }
}

/// Протокол дня в обычном markdown-файле: легко читать, искать и отдавать ассистенту.
enum ProtocolWriter {
    static var directory: URL { VoiceLog.support.appendingPathComponent("protocol") }

    static func append(_ line: VoiceLine) { put(time: line.time, text: line.text, service: false) }
    static func note(_ text: String) { put(time: Date(), text: text, service: true) }

    private static func put(time: Date, text: String, service: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"; day.locale = Locale(identifier: "ru_RU")
        let clock = DateFormatter(); clock.dateFormat = "HH:mm:ss"
        let file = directory.appendingPathComponent("\(day.string(from: time)).md")
        var out = ""
        if !fm.fileExists(atPath: file.path) {
            let title = DateFormatter(); title.dateFormat = "d MMMM yyyy"; title.locale = Locale(identifier: "ru_RU")
            out += "# Протокол · \(title.string(from: time))\n\n"
        }
        out += service ? "- \(clock.string(from: time))  _\(text)_\n" : "- \(clock.string(from: time))  \(text)\n"
        guard let data = out.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: data) }
        else { try? data.write(to: file) }
    }
}
