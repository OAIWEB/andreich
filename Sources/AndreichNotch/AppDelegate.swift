import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var brain: PetBrain!
    private var monitor: ClaudeMonitor!
    private var voice: VoiceListener!
    private var shelf: ShelfStore!
    private var limits: UsageMonitor!
    private var analyst: ProtocolAnalyst!
    private var dropCatcher: DropCatcher!
    private var notch: NotchController!
    private var petWindow: PetWindowController!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var gallery: NSWindow?
    private var rate = 0
    private var pollAcc = 0.0
    private var cancellables = Set<AnyCancellable>()
    private var lastTick = Date()
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let geometry = NotchGeometry.current() else { NSApp.terminate(nil); return }
        brain = PetBrain(geometry: geometry)
        monitor = ClaudeMonitor()
        voice = VoiceListener()
        shelf = ShelfStore()
        limits = UsageMonitor()
        analyst = ProtocolAnalyst(voice: voice, claude: monitor)
        // Радость и прогулки — только когда ВСЯ работа закончена. Пока Claude занят,
        // Андреич сидит в чёлке и не дёргается; как освободился — выпрыгнул и пошёл гулять.
        monitor.$isWorking.removeDuplicates().sink { [weak self] working in
            guard let self else { return }
            let was = self.brain.claudeWorking
            self.brain.claudeWorking = working
            if working { self.brain.sendHome() }
            else if was { self.brain.celebrate() }
        }.store(in: &cancellables)
        voice.$state.sink { [weak self] st in
            guard let self else { return }
            let on = st == .listening
            self.brain.listening = on
            if on { self.brain.sendHome() }      // чтобы слушать, Андреич возвращается домой
        }.store(in: &cancellables)
        notch = NotchController(geometry: geometry, brain: brain, monitor: monitor, voice: voice, shelf: shelf, limits: limits, analyst: analyst)
        dropCatcher = DropCatcher(vm: notch.vm, shelf: shelf)
        petWindow = PetWindowController(brain: brain, shelf: shelf)
        setupStatusItem()
        monitor.poll()
        if ProcessInfo.processInfo.environment["ANDREICH_MIC"] != nil { voice.start() }
        else { voice.restoreIfWasOn() }
        if let demo = ProcessInfo.processInfo.environment["ANDREICH_DEMO_SHELF"] { shelf.add([URL(fileURLWithPath: demo)]) }
        switch ProcessInfo.processInfo.environment["ANDREICH_TAB"] {
        case "shelf": notch.vm.tab = .shelf
        case "journal": notch.vm.tab = .journal
        default: break
        }
        if ProcessInfo.processInfo.environment["ANDREICH_GALLERY"] != nil { gallery = showPoseGallery() }
        if ProcessInfo.processInfo.environment["ANDREICH_WALK"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.brain.goForWalk() }
        }
        if ProcessInfo.processInfo.environment["ANDREICH_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.notch.vm.open() }
        }

        registerHotKey()
        // Приём перетаскиваний не может ждать опроса мыши: во время системного drag
        // наш таймер молчит. Глобальный монитор событий «вооружает» окна мгновенно.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] _ in
            guard let self else { return }
            let vm = self.notch.vm
            let zone = (vm.isOpen ? vm.openRect : vm.closedRect).insetBy(dx: -24, dy: -16)
            self.dropCatcher.arm(over: zone)
            if self.brain.mode != .home { self.petWindow.panel.ignoresMouseEvents = false }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.dropCatcher.disarm() }
        }
        setRate(60)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let g = NotchGeometry.current() else { return }
                self.brain.geometry = g
                self.notch.refreshGeometry(g)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { voice?.stop(byUser: false) }

    private func setRate(_ hz: Int) {
        guard hz != rate else { return }
        rate = hz
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / Double(hz), target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() {
        let now = Date()
        let dt = min(0.25, now.timeIntervalSince(lastTick))
        lastTick = now
        brain.tick(dt)
        let mouse = NSEvent.mouseLocation
        petWindow.sync(mouse: mouse)
        notch.vm.pollMouse(mouse, dt: dt)
        notch.updateMouse(mouse)
        syncRaccoon()
        pollAcc += dt
        if pollAcc >= 1.5 { pollAcc = 0; monitor.poll() }
        // дома и при закрытой чёлке хватает 15 Гц, на прогулке нужны все 60
        setRate(brain.mode == .home && !notch.vm.isOpen ? 15 : 60)
    }

    private func syncRaccoon() {
        let w = RaccoonWeb.shared
        w.applySavedVariant()
        let roaming = brain.mode != .home
        let slot = roaming ? "overlay" : (notch.vm.isOpen && notch.vm.tab == .assistant && w.slots["panel"]?.window != nil ? "panel" : "wing")
        w.attach(slot: slot)
        let facing: Int = roaming && (brain.pose == .walk) ? Int(brain.facing) : 0
        let fps: Int = slot == "wing" ? (brain.pose == .sleep ? 5 : 10) : (brain.pose == .walk ? 30 : 20)
        w.update(state: brain.pose.js, facing: facing, rotation: brain.rotation, scale: Double(brain.scale),
                 view: slot == "wing" ? "head" : "full", fps: fps)
    }

    // MARK: меню в строке меню
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Андреич")
        let menu = NSMenu()
        menu.addItem(withTitle: "Микрофон: включить / выключить   ⌥⌘M", action: #selector(mic), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Позвать погулять", action: #selector(walk), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Отправить домой", action: #selector(home), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Вид: кругляш / полный рост", action: #selector(switchVariant), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }
    @objc private func walk() { brain.goForWalk() }
    /// Глобальная клавиша ⌥⌘M: включить или выключить запись из любого приложения.
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.voice.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x414E_4452), id: 1)   // «ANDR»
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    @objc private func switchVariant() {
        let w = RaccoonWeb.shared
        let v = w.variant == "mini" ? "full" : "mini"
        w.setVariant(v)
        brain.footOffset = v == "mini" ? 39 : 43
    }

    @objc private func home() { brain.sendHome() }
    @objc private func mic() { voice.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
