import SwiftUI
import UniformTypeIdentifiers

private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

struct NotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var brain: PetBrain
    @EnvironmentObject var monitor: ClaudeMonitor
    @EnvironmentObject var voice: VoiceListener
    @EnvironmentObject var shelf: ShelfStore
    @State private var dropTargeted = false

    var body: some View {
        let closed = vm.closedBody
        let open = NotchViewModel.openSize
        let flare = NotchViewModel.flare
        let bodyW = vm.isOpen ? open.width : closed.width
        let h = vm.isOpen ? open.height : closed.height

        ZStack(alignment: .top) {
            NotchShape(topRadius: flare, bottomRadius: vm.isOpen ? 26 : 12)
                .fill(Color.black)
                .frame(width: bodyW + flare * 2, height: h)
            ClosedWings()
                .frame(width: closed.width, height: closed.height)
                .opacity(vm.isOpen ? 0 : 1)
                .contentShape(Rectangle())
                .onTapGesture { vm.toggle() }
            if vm.contentMounted {
                OpenPanel()
                    .frame(width: open.width, height: open.height, alignment: .top)
                    .clipped()
                    .opacity(vm.isOpen ? 1 : 0)
                    .allowsHitTesting(vm.isOpen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.isOpen)
        // приём файлов живёт в AppKit (DropView в NotchPanel.swift): SwiftUI-овый onDrop
        // в окне поверх меню-бара до вида не доходил
        .overlay(alignment: .top) {
            if vm.isDragOver {
                RoundedRectangle(cornerRadius: vm.isOpen ? 22 : 10)
                    .strokeBorder(tiffany, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Закрытая чёлка: слева индикаторы (запись и Claude), справа домик Андреича.
private struct ClosedWings: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var brain: PetBrain
    @EnvironmentObject var monitor: ClaudeMonitor
    @EnvironmentObject var voice: VoiceListener

    @EnvironmentObject var limits: UsageMonitor
    @EnvironmentObject var analyst: ProtocolAnalyst

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    if voice.state == .listening {
                        Image(systemName: voice.stallSince != nil || analyst.analysisError != nil
                              ? "exclamationmark.triangle.fill" : "mic.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(voice.stallSince != nil ? .red
                                             : analyst.analysisError != nil ? Color(red: 0.98, green: 0.76, blue: 0.25) : .red)
                    }
                    StatusDot(working: monitor.isWorking)
                }
                if let u = limits.usage { WingUsageBar(u: u) }
            }
            .frame(width: NotchViewModel.wing)
            Spacer(minLength: vm.geometry.notchSize.width)
            ZStack {
                if brain.mode == .home {
                    RaccoonSlot(name: "wing").frame(width: 42, height: 34)
                }
            }
            .frame(width: NotchViewModel.wing)
        }
    }
}

/// Полоска лимитов в чёлке: длина — остаток недели, цвет — как с дневной нормой.
private struct WingUsageBar: View {
    let u: UsageState
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4)
            Capsule().fill(u.color).frame(width: max(2, 36 * u.weeklyLeft / 100), height: 4)
                .opacity(u.stale ? 0.45 : 1)
        }
        .help("Недельных осталось \(Int(u.weeklyLeft))% · \(u.dayCaption) · \(u.dayExplain)")
    }
}

private struct StatusDot: View {
    let working: Bool
    var body: some View {
        Circle()
            .fill(working ? claudeOrange : Color.white.opacity(0.25))
            .frame(width: 9, height: 9)
    }
}

private struct OpenPanel: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var shelf: ShelfStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch vm.tab {
            case .assistant: AssistantView()
            case .journal: JournalView()
            case .shelf: ShelfView()
            }
            HStack(spacing: 6) {
                TabButton(icon: "sparkles", selected: vm.tab == .assistant, badge: 0) { vm.tab = .assistant }
                TabButton(icon: "doc.text", selected: vm.tab == .journal, badge: 0) { vm.tab = .journal }
                TabButton(icon: "tray.full.fill", selected: vm.tab == .shelf, badge: shelf.items.count) { vm.tab = .shelf }
            }
            .padding(.top, 7).padding(.trailing, 22)
        }
    }
}

private struct TabButton: View {
    let icon: String
    let selected: Bool
    let badge: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .black : .white.opacity(0.75))
                    .frame(width: 28, height: 22)
                    .background(Capsule().fill(selected ? tiffany : Color.white.opacity(0.14)))
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 8, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 3).background(Capsule().fill(Color.white)).offset(x: 5, y: -4)
                }
            }
        }.buttonStyle(.plain)
    }
}

private struct AssistantView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var brain: PetBrain
    @EnvironmentObject var monitor: ClaudeMonitor
    @EnvironmentObject var voice: VoiceListener
    @EnvironmentObject var analyst: ProtocolAnalyst

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Андреич и микрофон
            VStack(spacing: 8) {
                ZStack {
                    if brain.mode == .home {
                        RaccoonSlot(name: "panel").frame(width: 112, height: 112)
                    }
                    if brain.mode != .home {
                        Text("гуляет по экрану").font(.system(size: 10, design: .rounded)).foregroundColor(.white.opacity(0.6))
                            .offset(y: 38)
                    }
                }
                .frame(width: 100, height: 100)
                MicButton(state: voice.state) { voice.toggle() }
                Text(micCaption)
                    .font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.65))
            }
            .frame(width: 124)

            // Протокол
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Протокол").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                    Spacer(minLength: 0)
                    SummaryButton()
                }
                if voice.state == .listening { PipelineStatus() }
                if case .blocked(let m) = voice.state {
                    Text(m).font(.system(size: 11, design: .rounded)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(voice.lines.suffix(analyst.cards.isEmpty ? 3 : 2))) { l in
                    HStack(alignment: .top, spacing: 6) {
                        Text(Self.clock.string(from: l.time)).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                        Text(l.text).font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.9)).lineLimit(2)
                    }
                }
                if !voice.partial.isEmpty {
                    Text(voice.partial).font(.system(size: 11, design: .rounded)).italic().foregroundColor(.white.opacity(0.55)).lineLimit(2)
                }
                if voice.lines.isEmpty, voice.partial.isEmpty, voice.state == .off {
                    Text("Включите микрофон, и я буду слушать и записывать разговор.")
                        .font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.5))
                }
                Spacer(minLength: 2)
                SuggestionList()
            }
            .frame(width: 292, alignment: .topLeading)

            // Claude
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(monitor.isWorking ? claudeOrange : Color.white.opacity(0.3)).frame(width: 8, height: 8)
                    Text(monitor.isWorking ? "Claude работает" : "Claude отдыхает")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                }
                if monitor.sessions.isEmpty {
                    Text("сессий пока нет").font(.system(size: 11, design: .rounded)).foregroundColor(.white.opacity(0.5))
                }
                ForEach(Array(monitor.sessions.prefix(3))) { s in SessionRow(session: s) }
                Spacer(minLength: 2)
                LimitsBlock()

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, vm.geometry.notchSize.height + 6)
        .padding(.bottom, 16)
        .padding(.horizontal, 24)
    }

    private var micCaption: String {
        switch voice.state {
        case .off: return "микрофон выключен"
        case .starting: return "запускаю…"
        case .listening: return "слушаю"
        case .blocked: return "нет доступа"
        }
    }

    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
}

/// Лимиты подписки: неделя, дневная норма и пятичасовое окно.
private struct LimitsBlock: View {
    @EnvironmentObject var limits: UsageMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let u = limits.usage {
                HStack(spacing: 5) {
                    Text("Лимиты").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.85))
                    Spacer(minLength: 0)
                    Text("сброс через \(u.weekResetsIn)").font(.system(size: 9, design: .rounded)).foregroundColor(.white.opacity(0.4))
                }
                Bar(fill: u.weeklyUsed / 100, color: .white.opacity(0.75), height: 5)
                Text("за неделю истрачено \(fmt(u.weeklyUsed))%, осталось \(fmt(u.weeklyLeft))%")
                    .font(.system(size: 9.5, design: .rounded)).foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Bar(fill: u.dayFill, color: u.color, height: 5)
                Text(u.dayCaption)
                    .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(u.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(u.dayExplain)
                    .font(.system(size: 9, design: .rounded)).foregroundColor(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                Text("5 часов: \(fmt(u.fiveHourUsed))%, сброс через \(u.fiveHourResetsIn)")
                    .font(.system(size: 9, design: .rounded)).foregroundColor(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(limits.failure ?? "смотрю лимиты…")
                    .font(.system(size: 10, design: .rounded)).foregroundColor(.white.opacity(0.45))
            }
        }
    }
    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    struct Bar: View {
        let fill: Double
        let color: Color
        let height: CGFloat
        var body: some View {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(color).frame(width: max(2, g.size.width * min(1, max(0, fill))))
                }
            }
            .frame(height: height)
        }
    }
}

/// Одна строка про здоровье конвейера: слышу ли звук, когда был последний текст,
/// сколько фраз ждут разбора и когда он в последний раз прошёл. Нет проблем — серый спокойный тон,
/// есть — жёлтый или красный с причиной.
private struct PipelineStatus: View {
    @EnvironmentObject var voice: VoiceListener
    @EnvironmentObject var analyst: ProtocolAnalyst

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3)) { ctx in
            let now = ctx.date
            let (text, level) = describe(now)
            HStack(spacing: 5) {
                Circle().fill(color(level)).frame(width: 6, height: 6)
                Text(text).font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(level == 0 ? .white.opacity(0.45) : color(level))
                    .lineLimit(1)
            }
        }
    }

    private func ago(_ d: Date?, _ now: Date) -> String {
        guard let d else { return "ещё нет" }
        let s = max(0, Int(now.timeIntervalSince(d)))
        if s < 60 { return "\(s) с назад" }
        if s < 3600 { return "\(s / 60) мин назад" }
        return "\(s / 3600) ч назад"
    }

    /// level: 0 — норма, 1 — внимание, 2 — авария
    private func describe(_ now: Date) -> (String, Int) {
        if let since = voice.stallSince {
            return ("звук идёт, а текста нет уже \(Int(now.timeIntervalSince(since))) с — звук пишется в файл", 2)
        }
        if let err = analyst.analysisError {
            return ("разбор не идёт: \(err) · в очереди \(analyst.pendingCount)", 1)
        }
        let text = "текст: \(ago(voice.lastTextAt, now)) · разобрано \(ago(analyst.lastAnalysisAt, now))"
            + (analyst.pendingCount > 0 ? " · в очереди \(analyst.pendingCount)" : "")
        return (text, 0)
    }

    private func color(_ level: Int) -> Color {
        switch level {
        case 2: return Color(red: 0.95, green: 0.27, blue: 0.27)
        case 1: return Color(red: 0.98, green: 0.76, blue: 0.25)
        default: return tiffany
        }
    }
}

/// Кнопка «Сводка дня»: Андреич перечитывает протокол и открывает короткий отчёт.
private struct SummaryButton: View {
    @EnvironmentObject var analyst: ProtocolAnalyst
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        Button(action: { vm.tab = .journal; analyst.makeDailySummary() }) {
            Text(analyst.summaryState.isEmpty ? "сводка дня" : analyst.summaryState)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }.buttonStyle(.plain)
    }
}

/// Вкладка «Протокол»: весь день целиком и сводка — здесь, в чёлке, без внешних редакторов.
private struct JournalView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var analyst: ProtocolAnalyst
    @EnvironmentObject var voice: VoiceListener
    @State private var showSummary = false
    @State private var daysAgo = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: { daysAgo += 1; showSummary = false; analyst.reloadProtocol(daysAgo: daysAgo) }) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(analyst.hasProtocol(daysAgo: daysAgo + 1) ? 0.8 : 0.25))
                        .frame(width: 18, height: 18).background(Circle().fill(Color.white.opacity(0.1)))
                }.buttonStyle(.plain).disabled(!analyst.hasProtocol(daysAgo: daysAgo + 1)).help("Предыдущий день")
                Text(dayTitle).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white)
                if daysAgo > 0 {
                    Button(action: { daysAgo -= 1; showSummary = false; analyst.reloadProtocol(daysAgo: daysAgo) }) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 18, height: 18).background(Circle().fill(Color.white.opacity(0.1)))
                    }.buttonStyle(.plain).help("Следующий день")
                }
                if !analyst.summaryText.isEmpty {
                    Button(action: { showSummary.toggle() }) {
                        Text(showSummary ? "к протоколу" : "к сводке")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(tiffany))
                    }.buttonStyle(.plain)
                }
                if daysAgo == 0 {
                    Button(action: { analyst.makeDailySummary(); showSummary = true }) {
                        Text(analyst.summaryState.isEmpty ? (analyst.summaryText.isEmpty ? "собрать сводку" : "обновить сводку") : analyst.summaryState)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }.buttonStyle(.plain)
                }
                if !analyst.summaryText.isEmpty {
                    Button(action: { analyst.sendSummaryToTelegram() }) {
                        Text(analyst.tgState.isEmpty ? "в Телегу" : analyst.tgState)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }.buttonStyle(.plain).help("Отправить сводку ботом Андреевичем в личку")
                }
                Button(action: { analyst.openProtocolFolder() }) {
                    Image(systemName: "folder").font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 22, height: 19)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }.buttonStyle(.plain).help("Папка с протоколами в Finder")
                Spacer(minLength: 56)   // место под кнопки вкладок
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(bodyText.isEmpty ? "Пока пусто. Включите микрофон — записи появятся здесь." : bodyText)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                        .id("конец")
                }
                .onAppear { analyst.reloadProtocol(daysAgo: daysAgo); proxy.scrollTo("конец", anchor: .bottom) }
                .onChange(of: voice.lines.count) { _, _ in if daysAgo == 0 { analyst.reloadProtocol() } }
            }
        }
        .padding(.top, vm.geometry.notchSize.height + 6)
        .padding(.bottom, 14)
        .padding(.horizontal, 24)
    }

    private var dayTitle: String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        if showSummary, !analyst.summaryText.isEmpty { return "Сводка" }
        let f = DateFormatter(); f.dateFormat = "d MMMM"; f.locale = Locale(identifier: "ru_RU")
        switch daysAgo {
        case 0: return "Сегодня"
        case 1: return "Вчера"
        default: return f.string(from: date)
        }
    }

    private var bodyText: String {
        if showSummary, !analyst.summaryText.isEmpty { return analyst.summaryText }
        // без заголовка-решётки: он уже в шапке вкладки
        return analyst.protocolText
            .replacingOccurrences(of: "# ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Предложения Андреича по услышанному: принять в Напоминания или убрать.
private struct SuggestionList: View {
    @EnvironmentObject var analyst: ProtocolAnalyst
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !analyst.cards.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 9)).foregroundColor(tiffany)
                    Text("Андреич услышал").font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    if analyst.analyzing { ProgressView().controlSize(.mini) }
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(analyst.cards) { card in SuggestionRow(card: card) }
                }
            }
            .frame(maxHeight: 158)
        }
    }
}

private struct SuggestionRow: View {
    @EnvironmentObject var analyst: ProtocolAnalyst
    let card: SuggestionCard
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: card.icon).font(.system(size: 10)).foregroundColor(tiffany).padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.kind == .prompt ? "\(card.title) → «\(card.session)»"
                         : card.time.isEmpty ? card.title : "\(card.title) · \(card.time)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if !card.detail.isEmpty {
                        Text(card.detail).font(.system(size: 9.5, design: .rounded))
                            .foregroundColor(.white.opacity(0.55)).lineLimit(2)
                    }
                    if !card.status.isEmpty {
                        Text(card.status).font(.system(size: 9, design: .rounded)).foregroundColor(tiffany)
                    }
                }
                Spacer(minLength: 4)
                Button(action: { analyst.accept(card) }) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                        .frame(width: 18, height: 18).background(Circle().fill(tiffany))
                }.buttonStyle(.plain).help("В Напоминания")
                Button(action: { analyst.dismiss(card) }) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.7))
                        .frame(width: 18, height: 18).background(Circle().fill(Color.white.opacity(0.14)))
                }.buttonStyle(.plain).help("Убрать")
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }
}

private struct MicButton: View {
    let state: VoiceListener.State
    let action: () -> Void
    var body: some View {
        let on = state == .listening || state == .starting
        Button(action: action) {
            Image(systemName: on ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(on ? Color.red : Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    var body: some View {
        let working = Date().timeIntervalSince(session.lastActivity) < ClaudeMonitor.workWindow
        HStack(spacing: 6) {
            Circle().fill(working ? claudeOrange : Color.white.opacity(0.22)).frame(width: 6, height: 6)
            Text(session.title).lineLimit(1).font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(working ? 0.95 : 0.6))
            Spacer(minLength: 4)
            Text(relative(session.lastActivity)).font(.system(size: 10, design: .rounded)).foregroundColor(.white.opacity(0.4))
        }
    }
    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "сейчас" }
        if s < 3600 { return "\(s / 60) мин" }
        return "\(s / 3600) ч"
    }
}

