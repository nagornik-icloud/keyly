import AppKit
import Carbon.HIToolbox

final class HotKeyManager {
    static let shared = HotKeyManager()
    
    // Fixed Carbon hotkey ids: 1 — layout, 2 — errorFix, 3 — voiceToText (4–6: undo, palette, cheatsheet).
    private var layoutHotKeyRef: EventHotKeyRef?
    private var errorFixHotKeyRef: EventHotKeyRef?
    private var voiceHotKeyRef: EventHotKeyRef?
    private var undoHotKeyRef: EventHotKeyRef?
    private var paletteHotKeyRef: EventHotKeyRef?
    private var cheatsheetHotKeyRef: EventHotKeyRef?
    private var appHotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var appHotKeyCarbonIds: [UInt32: UUID] = [:]
    private var nextAppHotKeyId: UInt32 = 100
    private var customHotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var customHotKeyCarbonIds: [UInt32: UUID] = [:]
    private var nextCustomHotKeyId: UInt32 = 300
    private var customModules: [CustomAIModule] = []
    private var snippetHotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var snippetHotKeyCarbonIds: [UInt32: UUID] = [:]
    private var nextSnippetHotKeyId: UInt32 = 500
    private var snippets: [Snippet] = []
    private var eventHandler: EventHandlerRef?
    private var keyEventTap: CFMachPort?
    private var keyEventTapSource: CFRunLoopSource?
    private var isHotKeyHandlingSuspended = false
    private var recordingBlockCount = 0
    private var isInsertingSnippet = false
    
    private(set) var layoutSwitchCombo: KeyCombo?
    private(set) var errorFixCombo: KeyCombo?
    private(set) var voiceToTextCombo: KeyCombo?
    private(set) var undoCombo: KeyCombo?
    private(set) var paletteCombo: KeyCombo?
    private(set) var cheatsheetCombo: KeyCombo?
    private var appLaunchShortcuts: [AppLaunchShortcut] = []
    
    private init() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(customHotKeyChanged(_:)),
                                               name: .customHotKeyChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(customHotKeyChanged(_:)),
                                               name: .appHotKeysChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(customModulesChanged),
                                               name: .customAIModulesChanged,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(snippetsChangedHandler),
                                               name: .snippetsChanged,
                                               object: nil)
    }
    
    func start() {
        hotKeysIntended = true
        loadCombos()
        loadCustomModules()
        loadSnippets()
        installEventHandlerIfNeeded()
        updateLayoutSwitchHotKey(combo: layoutSwitchCombo)
        updateErrorFixHotKey(combo: errorFixCombo)
        updateVoiceHotKey(combo: voiceToTextCombo)
        updateUndoHotKey(combo: undoCombo)
        updatePaletteHotKey(combo: paletteCombo)
        updateCheatsheetHotKey(combo: cheatsheetCombo)
        registerAppHotKeys()
        registerCustomHotKeys()
        registerSnippetHotKeys()
        installKeyEventTapIfNeeded()
    }
    
    // MARK: - Event tap health

    /// How many consecutive polls saw a dead tap. The threshold keeps the alarm from flashing on
    /// every routine `tapDisabledByTimeout` — the callback fixes that within milliseconds, and
    /// blinking the icon on it would be noise, not a signal.
    private var tapDownStreak = 0

    /// The tap has been dead longer than the threshold. Read by the UI for the alarm icon and banner.
    private(set) var tapIsUnhealthy = false

    /// Tap health poll. Called once a second from `AppDelegate`.
    ///
    /// Why poll when there is a callback: the callback fires on `tapDisabledByTimeout` and
    /// `ByUserInput`, but REVOKING the Accessibility permission doesn't arrive AT ALL — the tap
    /// just stops receiving events, and from outside that is indistinguishable from "the user
    /// pressed nothing". The only way to know is to ask the system ourselves.
    ///
    /// Returns `true` if the alarm state CHANGED (the UI has something to update).
    @discardableResult
    func pollTapHealth() -> Bool {
        guard hotKeysAreRunning else {
            // The tap is intentionally not running (no permission, paused) — not a failure.
            return setUnhealthy(false)
        }
        let alive: Bool
        if let tap = keyEventTap {
            alive = CGEvent.tapIsEnabled(tap: tap)
            if !alive {
                CGEvent.tapEnable(tap: tap, enable: true)
                Log.warn(.hotKey, "HotKeyManager: тап был выключен — включаем (попытка \(tapDownStreak + 1))")
            }
        } else {
            alive = false
            if tapDownStreak % 30 == 0 {
                Log.warn(.hotKey, "HotKeyManager: тапа НЕТ — пересоздаём (попытка \(tapDownStreak + 1))")
            }
            installKeyEventTapIfNeeded()   // only the tap, not a full re-registration every second
        }
        if alive {
            tapDownStreak = 0
            return setUnhealthy(false)
        }
        tapDownStreak += 1
        // Threshold: three failed attempts. Polling once a second that's ~3 s of continuous
        // death — enough for a routine timeout to recover on its own.
        return setUnhealthy(tapDownStreak >= 3)
    }

    private func setUnhealthy(_ value: Bool) -> Bool {
        guard tapIsUnhealthy != value else { return false }
        tapIsUnhealthy = value
        Log.error(.hotKey, value
                  ? "HotKeyManager: тап НЕ поднимается \(tapDownStreak) попыток подряд — тревога"
                  : "HotKeyManager: тап снова жив, тревога снята")
        NotificationCenter.default.post(name: .eventTapHealthChanged, object: nil)
        return true
    }

    /// Hotkeys are meant to run (start() called, not stopped). Judged by intent, not by the
    /// tap: when tapCreate fails the tap is nil, and "no tap" must raise the alarm,
    /// not read as "intentionally stopped".
    private var hotKeysAreRunning: Bool { hotKeysIntended }
    private var hotKeysIntended = false

    func stop() {
        hotKeysIntended = false
        if let hotKey = layoutHotKeyRef {
            UnregisterEventHotKey(hotKey)
            layoutHotKeyRef = nil
            Log.warn(.hotKey, "HotKeyManager: Горячая клавиша (layout) отменена")
        }
        if let hotKey = errorFixHotKeyRef {
            UnregisterEventHotKey(hotKey)
            errorFixHotKeyRef = nil
            Log.warn(.hotKey, "HotKeyManager: Горячая клавиша (errorFix) отменена")
        }
        if let hotKey = paletteHotKeyRef {
            UnregisterEventHotKey(hotKey)
            paletteHotKeyRef = nil
        }
        if let hotKey = undoHotKeyRef {
            UnregisterEventHotKey(hotKey)
            undoHotKeyRef = nil
        }
        if let hotKey = cheatsheetHotKeyRef {
            UnregisterEventHotKey(hotKey)
            cheatsheetHotKeyRef = nil
        }
        if let hotKey = voiceHotKeyRef {
            UnregisterEventHotKey(hotKey)
            voiceHotKeyRef = nil
            Log.warn(.hotKey, "HotKeyManager: Горячая клавиша (voiceToText) отменена")
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
            Log.info(.hotKey, "HotKeyManager: Обработчик горячих клавиш удалён")
        }
        if let tap = keyEventTap, let source = keyEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFMachPortInvalidate(tap)
            keyEventTap = nil
            keyEventTapSource = nil
            Log.info(.hotKey, "HotKeyManager: EventTap для сырых клавиш остановлен")
        }
        appHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        appHotKeyRefs.removeAll()
        appHotKeyCarbonIds.removeAll()
        nextAppHotKeyId = 100
        customHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        customHotKeyRefs.removeAll()
        customHotKeyCarbonIds.removeAll()
        nextCustomHotKeyId = 300
        snippetHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        snippetHotKeyRefs.removeAll()
        snippetHotKeyCarbonIds.removeAll()
        nextSnippetHotKeyId = 500
        recordingBlockCount = 0
        isHotKeyHandlingSuspended = false
    }
    
    // MARK: - Suspending hotkeys while recording
    
    func setRecordingMode(_ isRecording: Bool) {
        if isRecording {
            recordingBlockCount += 1
            suspendHotKeysForRecording()
        } else {
            recordingBlockCount = max(0, recordingBlockCount - 1)
            if recordingBlockCount == 0 {
                resumeHotKeysAfterRecording()
            }
        }
    }
    
    private func suspendHotKeysForRecording() {
        guard !isHotKeyHandlingSuspended else { return }
        isHotKeyHandlingSuspended = true
        
        if let hotKey = layoutHotKeyRef {
            UnregisterEventHotKey(hotKey)
            layoutHotKeyRef = nil
        }
        if let hotKey = errorFixHotKeyRef {
            UnregisterEventHotKey(hotKey)
            errorFixHotKeyRef = nil
        }
        if let hotKey = voiceHotKeyRef {
            UnregisterEventHotKey(hotKey)
            voiceHotKeyRef = nil
        }
        appHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        appHotKeyRefs.removeAll()
        appHotKeyCarbonIds.removeAll()
        snippetHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        snippetHotKeyRefs.removeAll()
        snippetHotKeyCarbonIds.removeAll()
        Log.info(.hotKey, "HotKeyManager: Хоткеи временно приостановлены на время записи")
    }
    
    private func resumeHotKeysAfterRecording() {
        guard isHotKeyHandlingSuspended else { return }
        isHotKeyHandlingSuspended = false
        installEventHandlerIfNeeded()
        updateLayoutSwitchHotKey(combo: layoutSwitchCombo)
        updateErrorFixHotKey(combo: errorFixCombo)
        updateVoiceHotKey(combo: voiceToTextCombo)
        updateUndoHotKey(combo: undoCombo)
        updatePaletteHotKey(combo: paletteCombo)
        updateCheatsheetHotKey(combo: cheatsheetCombo)
        registerAppHotKeys()
        registerSnippetHotKeys()
        Log.info(.hotKey, "HotKeyManager: Хоткеи снова активны после записи")
    }
    
    // MARK: - Updating hotkeys
    
    private func updateLayoutSwitchHotKey(combo: KeyCombo?) {
        updateCarbonHotKey(combo: combo, ref: &layoutHotKeyRef, carbonId: 1, field: HotKeyFieldID.layout)
    }

    private func updateErrorFixHotKey(combo: KeyCombo?) {
        updateCarbonHotKey(combo: combo, ref: &errorFixHotKeyRef, carbonId: 2, field: HotKeyFieldID.errorFix)
    }

    private func updateVoiceHotKey(combo: KeyCombo?) {
        updateCarbonHotKey(combo: combo, ref: &voiceHotKeyRef, carbonId: 3, field: HotKeyFieldID.voice)
    }

    private func updateUndoHotKey(combo: KeyCombo?) {
        updateCarbonHotKey(combo: combo, ref: &undoHotKeyRef, carbonId: 4, field: HotKeyFieldID.undo)
    }

    private func updatePaletteHotKey(combo: KeyCombo?) {
        updateCarbonHotKey(combo: combo, ref: &paletteHotKeyRef, carbonId: 5, field: HotKeyFieldID.snippetPalette)
    }

    private func updateCheatsheetHotKey(combo: KeyCombo?) {
        updateCarbonHotKey(combo: combo, ref: &cheatsheetHotKeyRef, carbonId: 6, field: HotKeyFieldID.cheatsheet)
    }

    private func updateCarbonHotKey(combo: KeyCombo?, ref: inout EventHotKeyRef?, carbonId: UInt32, field name: String) {
        guard !isHotKeyHandlingSuspended else { return }

        if let hotKey = ref {
            UnregisterEventHotKey(hotKey)
            ref = nil
        }

        guard let combo else {
            Log.warn(.hotKey, "HotKeyManager: Хоткей \(name) не установлен")
            return
        }

        if combo.isSystemKey {
            Log.warn(.hotKey, "HotKeyManager: \(name) системная клавиша — EventTap обработает, Carbon пропускаем")
            return
        }

        if combo.modifiers.isEmpty {
            Log.info(.hotKey, "HotKeyManager: \(name) без модификаторов — используем EventTap, Carbon не регистрируем")
            return
        }

        let carbonModifiers = Self.carbonFlags(from: combo.modifiers)
        let sigValue = "HkMg".utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let hotKeyID = EventHotKeyID(signature: OSType(sigValue), id: carbonId)

        let status = RegisterEventHotKey(UInt32(combo.keyCode),
                                         carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        HotKeyRegistrationStatus.shared.report(fieldID: name, succeeded: status == noErr)
        if status == noErr {
            Log.info(.hotKey, "HotKeyManager: Хоткей \(name) зарегистрирован — keyCode: \(combo.keyCode), mods: \(carbonModifiers)")
        } else {
            Log.error(.hotKey, "HotKeyManager: Ошибка регистрации хоткея \(name), status=\(status)")
        }
    }
    
    private func registerAppHotKeys() {
        appHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        appHotKeyRefs.removeAll()
        appHotKeyCarbonIds.removeAll()
        nextAppHotKeyId = 100
        
        guard !isHotKeyHandlingSuspended else { return }

        // Clear the previous pass's marks ENTIRELY: otherwise a deleted target would stay "not
        // working" forever, since nobody would report on its id again.
        HotKeyRegistrationStatus.shared.clear(prefix: "app.")

        let sigValue = "HkAp".utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        
        for shortcut in appLaunchShortcuts {
            guard let combo = shortcut.keyCombo else { continue }
            if combo.isSystemKey || combo.modifiers.isEmpty {
                // System and bare keys are handled by the event tap.
                continue
            }
            
            let carbonModifiers = Self.carbonFlags(from: combo.modifiers)
            let hotKeyID = EventHotKeyID(signature: OSType(sigValue), id: nextAppHotKeyId)
            var ref: EventHotKeyRef?
            
            let statusRegister = RegisterEventHotKey(UInt32(combo.keyCode),
                                                     carbonModifiers,
                                                     hotKeyID,
                                                     GetApplicationEventTarget(),
                                                     0,
                                                     &ref)
            HotKeyRegistrationStatus.shared.report(fieldID: HotKeyFieldID.app(shortcut.id),
                                                   succeeded: statusRegister == noErr)
            if statusRegister == noErr {
                if let ref = ref {
                    appHotKeyRefs[shortcut.id] = ref
                }
                appHotKeyCarbonIds[nextAppHotKeyId] = shortcut.id
                Log.info(.hotKey, "HotKeyManager: Хоткей приложения \(shortcut.displayName) зарегистрирован - keyCode: \(combo.keyCode), modifiers: \(carbonModifiers)")
                nextAppHotKeyId += 1
            } else {
                Log.error(.hotKey, "HotKeyManager: Ошибка регистрации хоткея приложения \(shortcut.displayName), status=\(statusRegister)")
            }
        }
    }
    
    private func loadCustomModules() {
        customModules = CustomModuleStore.load()
    }
    
    private func registerCustomHotKeys() {
        customHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        customHotKeyRefs.removeAll()
        customHotKeyCarbonIds.removeAll()
        nextCustomHotKeyId = 300
        
        guard !isHotKeyHandlingSuspended else { return }
        HotKeyRegistrationStatus.shared.clear(prefix: "custom.")
        let sigValue = "HkCM".utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        for module in customModules {
            // A switched-off module must not hold its shortcut.
            guard module.isEnabled, let combo = module.hotKey else { continue }
            if combo.isSystemKey || combo.modifiers.isEmpty {
                continue
            }
            let carbonModifiers = Self.carbonFlags(from: combo.modifiers)
            let hotKeyID = EventHotKeyID(signature: OSType(sigValue), id: nextCustomHotKeyId)
            var ref: EventHotKeyRef?
            let statusRegister = RegisterEventHotKey(UInt32(combo.keyCode),
                                                     carbonModifiers,
                                                     hotKeyID,
                                                     GetApplicationEventTarget(),
                                                     0,
                                                     &ref)
            HotKeyRegistrationStatus.shared.report(fieldID: HotKeyFieldID.customModule(module.id),
                                                   succeeded: statusRegister == noErr)
            if statusRegister == noErr {
                if let ref = ref {
                    customHotKeyRefs[module.id] = ref
                }
                customHotKeyCarbonIds[nextCustomHotKeyId] = module.id
                Log.info(.hotKey, "HotKeyManager: Хоткей кастомного модуля \(module.name) зарегистрирован - keyCode: \(combo.keyCode), modifiers: \(carbonModifiers)")
                nextCustomHotKeyId += 1
            } else {
                Log.error(.hotKey, "HotKeyManager: Ошибка регистрации хоткея кастомного модуля \(module.name)")
            }
        }
    }
    
    private func loadSnippets() {
        snippets = SnippetStore.load()
    }

    private func registerSnippetHotKeys() {
        snippetHotKeyRefs.values.forEach { UnregisterEventHotKey($0) }
        snippetHotKeyRefs.removeAll()
        snippetHotKeyCarbonIds.removeAll()
        nextSnippetHotKeyId = 500

        guard !isHotKeyHandlingSuspended else { return }
        HotKeyRegistrationStatus.shared.clear(prefix: "snippet.")
        let sigValue = "HkSn".utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        for snippet in snippets {
            guard snippet.isEnabled else { continue }
            guard let combo = snippet.hotKey else { continue }
            if combo.isSystemKey || combo.modifiers.isEmpty { continue }
            let carbonModifiers = Self.carbonFlags(from: combo.modifiers)
            let hotKeyID = EventHotKeyID(signature: OSType(sigValue), id: nextSnippetHotKeyId)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(combo.keyCode),
                                             carbonModifiers,
                                             hotKeyID,
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            HotKeyRegistrationStatus.shared.report(fieldID: HotKeyFieldID.snippet(snippet.id),
                                                   succeeded: status == noErr)
            if status == noErr {
                if let ref { snippetHotKeyRefs[snippet.id] = ref }
                snippetHotKeyCarbonIds[nextSnippetHotKeyId] = snippet.id
                Log.info(.hotKey, "HotKeyManager: Хоткей сниппета \(snippet.id.uuidString.prefix(8)) зарегистрирован")
                nextSnippetHotKeyId += 1
            } else {
                Log.error(.hotKey, "HotKeyManager: Ошибка регистрации хоткея сниппета \(snippet.id.uuidString.prefix(8))")
            }
        }
    }

    // MARK: - Event handler
    
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        
        let eventHandlerCallback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return noErr }
            
            let id = hotKeyID.id
            guard !HotKeyManager.shared.isHotKeyHandlingSuspended else { return noErr }
            // Pause silences the Carbon path too: modifier hotkeys bypass the event tap, and without
            // this gate half the combos would keep working while paused.
            guard !AppPause.isPaused else { return noErr }
            
            DispatchQueue.main.async {
                switch id {
                case 1:
                    TextSelector.selectWordToLeft(hotKeyEventTime: Date())
                    Log.info(.hotKey, "HotKeyManager: Нажат хоткей layout, вызван selectWordToLeft")
                case 2:
                    Task {
                        await ErrorFixer.shared.run()
                    }
                    Log.info(.hotKey, "HotKeyManager: Нажат хоткей errorFix, вызван ErrorFixer.run()")
                case 5:
                    SnippetPaletteController.shared.toggle()
                    Log.info(.hotKey, "HotKeyManager: Нажат хоткей палитры сниппетов")
                case 6:
                    CheatsheetController.shared.toggle()
                    Log.info(.hotKey, "HotKeyManager: Нажат хоткей шпаргалки")
                case 4:
                    Task { await UndoActionService.shared.undoLastAction() }
                    Log.info(.hotKey, "HotKeyManager: Нажат хоткей undo")
                case 3:
                    VoiceToTextManager.shared.startSession()
                    Log.info(.hotKey, "HotKeyManager: Нажат хоткей voiceToText, вызван VoiceToTextManager.startSession()")
                default:
                    if let shortcutId = HotKeyManager.shared.appHotKeyCarbonIds[id],
                       let shortcut = HotKeyManager.shared.appLaunchShortcuts.first(where: { $0.id == shortcutId }) {
                        HotKeyManager.shared.launchApp(shortcut)
                    } else if let moduleId = HotKeyManager.shared.customHotKeyCarbonIds[id],
                              let module = HotKeyManager.shared.customModules.first(where: { $0.id == moduleId }) {
                        Task {
                            await CustomModuleRunner.shared.run(module: module)
                        }
                    } else if let snippetId = HotKeyManager.shared.snippetHotKeyCarbonIds[id],
                              let snippet = HotKeyManager.shared.snippets.first(where: { $0.id == snippetId }),
                              snippet.isEnabled {
                        Task { @MainActor in
                            SnippetService.shared.insert(snippet)
                        }
                    }
                }
            }
            
            return noErr
        }
        
        let statusHandler = InstallEventHandler(GetApplicationEventTarget(),
                                                eventHandlerCallback,
                                                1,
                                                &eventType,
                                                nil,
                                                &eventHandler)
        if statusHandler != noErr {
            Log.error(.hotKey, "HotKeyManager: Ошибка установки обработчика горячих клавиш")
        }
    }
    
    // MARK: - Menu bar triggers (same path as hotkeys — instant action from the menu)
    func menuTriggerLayoutSwitch() { TextSelector.selectWordToLeft(hotKeyEventTime: Date()) }
    func menuTriggerErrorFix() { Task { await ErrorFixer.shared.run() } }
    func menuTriggerVoice() { VoiceToTextManager.shared.startSession() }
    func menuLaunchApp(_ shortcut: AppLaunchShortcut) { launchApp(shortcut) }
    func menuRunCustom(_ module: CustomAIModule) { Task { await CustomModuleRunner.shared.run(module: module) } }
    var menuAppShortcuts: [AppLaunchShortcut] { appLaunchShortcuts }

    private func installKeyEventTapIfNeeded() {
        #if DEBUG
        // Preview mode (redesign preview) does NOT intercept input — it's a window to click around
        // in, not a working interceptor. Otherwise a dev build would meddle with the user's keystrokes.
        if ProcessInfo.processInfo.environment["KEYLY_PREVIEW"] == "1" { return }
        #endif
        guard keyEventTap == nil else { return }
        
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
                   (CGEventMask(1) << CGEventMask(kNXSystemDefined))
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else {
                return Unmanaged.passUnretained(event)
            }
            
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = manager.keyEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    Log.info(.hotKey, "HotKeyManager: EventTap был отключён, включаем снова")
                }
                return Unmanaged.passUnretained(event)
            }
            
            let isSystemDefined = type.rawValue == kNXSystemDefined
            guard type == .keyDown || isSystemDefined else { return Unmanaged.passUnretained(event) }
            
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleRawEvent(event: event)
        }
        
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        else {
            if tapDownStreak % 30 == 0 {
                Log.error(.hotKey, "HotKeyManager: Не удалось создать EventTap для сырых клавиш")
            }
            return
        }
        
        keyEventTap = tap
        keyEventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = keyEventTapSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.info(.hotKey, "HotKeyManager: EventTap для сырых клавиш установлен")
        }
    }
    
    private func handleRawEvent(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Pause turns off ALL hotkeys at once — one gate at the entry, not a check in every branch:
        // a copy of the condition in six places would drift, and one hotkey would keep working
        // while paused as a random glitch.
        if AppPause.isPaused { return Unmanaged.passUnretained(event) }

        // Detect our own synthetic events (backspace / Cmd+V from SnippetService etc.) — they must
        // not be swallowed, otherwise we'd block our own paste.
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        let isOurSynthetic = pid == ProcessInfo.processInfo.processIdentifier

        // While a snippet is being inserted, swallow live user input so keystrokes don't
        // squeeze in between our backspaces and Cmd+V.
        if !isOurSynthetic, isInsertingSnippet {
            return nil
        }

        // Don't record our own synthetic events in the buffer — otherwise live voice-to-text
        // typing pollutes snippet triggers (the last N keystrokes become ours, not the user's).
        if !isOurSynthetic {
            InputMonitor.shared.record(cgEvent: event)
        }

        if !isOurSynthetic, checkSnippetTriggers() {
            // A trigger matched right now — swallow the trigger keystroke itself so it never
            // reaches the app. Then we need to delete one character fewer, see the logic in insert.
            return nil
        }

        if isHotKeyHandlingSuspended {
            return Unmanaged.passUnretained(event)
        }
        
        if let systemInfo = systemKeyInfo(from: event) {
            #if DEBUG
            Log.info(.hotKey, "HotKeyManager: systemDefined keyCode=\(systemInfo.keyCode) state=0x\(String(systemInfo.rawState, radix: 16)) repeat=\(systemInfo.isRepeat) mods=\(systemInfo.modifiers)")
            #endif
            if let combo = voiceToTextCombo, combo.isSystemKey, matches(systemInfo: systemInfo, combo: combo) {
                if systemInfo.isKeyDown {
                    DispatchQueue.main.async {
                        VoiceToTextManager.shared.startSession()
                    }
                }
                return nil
            }
            if let combo = layoutSwitchCombo, combo.isSystemKey, matches(systemInfo: systemInfo, combo: combo) {
                if systemInfo.isKeyDown {
                    let referenceDate = InputMonitor.shared.referenceDate(from: event) ?? Date()
                    DispatchQueue.main.async {
                        TextSelector.selectWordToLeft(hotKeyEventTime: referenceDate)
                        Log.info(.hotKey, "HotKeyManager: RawTap — selectWordToLeft (layout, systemKey)")
                    }
                    return nil
                }
            }
            if let combo = errorFixCombo, combo.isSystemKey, matches(systemInfo: systemInfo, combo: combo) {
                if systemInfo.isKeyDown {
                    DispatchQueue.main.async {
                        Task {
                            await ErrorFixer.shared.run()
                        }
                        Log.info(.hotKey, "HotKeyManager: RawTap — ErrorFixer.run() (systemKey)")
                    }
                    return nil
                }
            }
            

            for shortcut in appLaunchShortcuts {
                guard let combo = shortcut.keyCombo, combo.isSystemKey else { continue }
                if matches(systemInfo: systemInfo, combo: combo) {
                    if systemInfo.isKeyDown {
                        DispatchQueue.main.async {
                            self.launchApp(shortcut)
                        }
                    }
                    return nil
                }
            }
            
            for module in HotKeyManager.shared.customModules {
                guard module.isEnabled, let combo = module.hotKey, combo.isSystemKey else { continue }
                if matches(systemInfo: systemInfo, combo: combo) {
                    if systemInfo.isKeyDown {
                        DispatchQueue.main.async {
                            Task { await CustomModuleRunner.shared.run(module: module) }
                        }
                    }
                    return nil
                }
            }

            for snippet in HotKeyManager.shared.snippets {
                guard snippet.isEnabled else { continue }
                guard let combo = snippet.hotKey, combo.isSystemKey else { continue }
                if matches(systemInfo: systemInfo, combo: combo) {
                    if systemInfo.isKeyDown {
                        DispatchQueue.main.async {
                            Task { @MainActor in SnippetService.shared.insert(snippet) }
                        }
                    }
                    return nil
                }
            }
            for (combo, action) in fixedTapActions {
                guard let combo, combo.isSystemKey, matches(systemInfo: systemInfo, combo: combo) else { continue }
                if systemInfo.isKeyDown, !systemInfo.isRepeat { DispatchQueue.main.async(execute: action) }
                return nil
            }
        }
        
        if let combo = voiceToTextCombo, matchesRaw(event: event, combo: combo) {
            // A hotkey press is not "typed text": remove it from the buffer, otherwise features
            // reading the buffer would glue the key's character to the word.
            InputMonitor.shared.dropLastRecorded()
            DispatchQueue.main.async {
                VoiceToTextManager.shared.startSession()
            }
            return nil // block the system action (e.g. dictation or a media key)
        }
        if let combo = layoutSwitchCombo, matchesRaw(event: event, combo: combo) {
            // A hotkey press is not "typed text": remove it from the buffer, otherwise features
            // reading the buffer would glue the key's character to the word.
            InputMonitor.shared.dropLastRecorded()
            let referenceDate = InputMonitor.shared.referenceDate(from: event) ?? Date()
            DispatchQueue.main.async {
                TextSelector.selectWordToLeft(hotKeyEventTime: referenceDate)
                Log.info(.hotKey, "HotKeyManager: RawTap — selectWordToLeft (layout)")
            }
            return nil
        }
        if let combo = errorFixCombo, matchesRaw(event: event, combo: combo) {
            // A hotkey press is not "typed text": remove it from the buffer, otherwise features
            // reading the buffer would glue the key's character to the word.
            InputMonitor.shared.dropLastRecorded()
            DispatchQueue.main.async {
                Task {
                    await ErrorFixer.shared.run()
                }
                Log.info(.hotKey, "HotKeyManager: RawTap — ErrorFixer.run()")
            }
            return nil
        }
        if let shortcut = appLaunchShortcuts.first(where: { shortcut in
            guard let combo = shortcut.keyCombo else { return false }
            guard !combo.isSystemKey, combo.modifiers.isEmpty else { return false }
            return matchesRaw(event: event, combo: combo)
        }) {
            // A bare hotkey key is not "typed text" either (see dropLastRecorded).
            InputMonitor.shared.dropLastRecorded()
            DispatchQueue.main.async {
                self.launchApp(shortcut)
            }
            return nil
        }
        if let module = customModules.first(where: { module in
            guard module.isEnabled else { return false } // a disabled module doesn't fire
            guard let combo = module.hotKey else { return false }
            guard !combo.isSystemKey else { return false }
            guard combo.modifiers.isEmpty else { return false }
            return matchesRaw(event: event, combo: combo)
        }) {
            InputMonitor.shared.dropLastRecorded()
            DispatchQueue.main.async {
                Task { await CustomModuleRunner.shared.run(module: module) }
            }
            return nil
        }
        if let snippet = snippets.first(where: { snippet in
            guard snippet.isEnabled else { return false }
            guard let combo = snippet.hotKey else { return false }
            guard !combo.isSystemKey, combo.modifiers.isEmpty else { return false }
            return matchesRaw(event: event, combo: combo)
        }) {
            InputMonitor.shared.dropLastRecorded()
            DispatchQueue.main.async {
                Task { @MainActor in SnippetService.shared.insert(snippet) }
            }
            return nil
        }
        // Undo / palette / cheatsheet on a bare key — checked LAST so a key already used by an
        // app, module or snippet keeps doing what it did. Our own synthetic keystrokes and
        // key auto-repeat must not fire them (a held key would toggle the palette on and off).
        if !isOurSynthetic,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           let (_, action) = fixedTapActions.first(where: { combo, _ in
               guard let combo, !combo.isSystemKey, combo.modifiers.isEmpty else { return false }
               return matchesRaw(event: event, combo: combo)
           }) {
            InputMonitor.shared.dropLastRecorded()
            DispatchQueue.main.async(execute: action)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
    
    /// Undo, snippet palette and cheatsheet with a bare or media key: Carbon can't register
    /// those, so the tap handles them — same actions as the Carbon path (ids 4–6).
    private var fixedTapActions: [(KeyCombo?, () -> Void)] {
        [
            (undoCombo, { Task { await UndoActionService.shared.undoLastAction() } }),
            (paletteCombo, { SnippetPaletteController.shared.toggle() }),
            (cheatsheetCombo, { CheatsheetController.shared.toggle() }),
        ]
    }

    // MARK: - Trigger sequence detection

    /// Deferred match of an ambiguous trigger (see `schedulePendingSnippet`).
    private var pendingSnippetWork: DispatchWorkItem?

    /// Returns true if a trigger just fired. In that case the caller (handleRawEvent)
    /// swallows the current keystroke so it doesn't reach the app.
    @discardableResult
    private func checkSnippetTriggers() -> Bool {
        guard !isHotKeyHandlingSuspended, !isInsertingSnippet else { return false }
        // Never run triggers in our own settings window.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }
        // Match by the LONGEST matching trigger, not the first in the list.
        //
        // This used to be a double loop where "first match wins", and list order silently decided
        // which snippet fired: dragging a row changed product behavior.
        // `SnippetSearch.matchByLongestTrigger` was written and tested exactly for this — and was
        // called from nowhere but `Tests/`.
        //
        // Match by ACTUALLY TYPED characters, not by the physical US-ANSI keyCode: on a non-US
        // layout the character lives on a DIFFERENT key (on the Russian layout `"` is Shift+2), and a
        // keycode mapping would NEVER match.
        //
        // At least 2 characters: a one-character trigger would fire on every keystroke.
        let eligible = snippets.filter { s in
            s.isEnabled && s.triggers.contains { $0.count >= 2 }
        }
        let longest = eligible.flatMap(\.triggers).map(\.count).max() ?? 0
        guard longest >= 2 else { return false }
        // +1 to the window: in "after separator" mode the tail ends with the separator, and the
        // word itself starts one character earlier.
        let typed = InputMonitor.shared.lastNTypedCharacters(count: longest + 1)
        let justTyped = typed.last

        // A new keystroke arrived — the previous deferred match is no longer relevant,
        // recompute from scratch.
        cancelPendingSnippet()

        guard let hit = SnippetSearch.match(typed: typed, justTyped: justTyped, in: eligible),
              hit.trigger.count >= 2 else { return false }

        // The matched trigger may be the START of a longer one ("addr" inside "address"). Creating
        // such pairs is now forbidden, but for already saved ones the window remains a safety net:
        // keep typing — the long one wins, stop — the short one fires.
        // In "after separator" mode there's nothing to wait for: the separator already ended the word.
        if hit.separator == nil,
           SnippetSearch.hasLongerTriggerStarting(with: hit.trigger, in: eligible) {
            schedulePendingSnippet(snippet: hit.snippet, trigger: hit.trigger)
            // false — the keystroke goes to the app as a regular character: we don't know yet whether
            // it's a trigger or the start of a longer one, and a swallowed letter can't be returned.
            return false
        }

        // How many to erase. "Immediately": the last keystroke is swallowed and never reaches the
        // app — so one character fewer. "After separator": the separator is swallowed, and the
        // trigger letters are already typed — erase them all.
        let toDelete = hit.separator == nil ? max(0, hit.trigger.count - 1) : hit.trigger.count
        // Another text operation running → the keystroke must reach the app, not vanish.
        return fireSnippet(hit.snippet, trigger: hit.trigger,
                           deleting: toDelete, separator: hit.separator)
    }

    /// Wait window for a longer trigger. 600 ms — noticeably longer than the pause between
    /// letters within a word and noticeably shorter than the "I'm done, looking at the result" pause.
    private static let triggerAmbiguityWindow: TimeInterval = 0.6

    private func schedulePendingSnippet(snippet: Snippet, trigger: String) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSnippetWork = nil
            // Full length, NOT length-1: the ambiguous keystroke was passed through to the app,
            // so all trigger characters must be erased.
            self.fireSnippet(snippet, trigger: trigger, deleting: trigger.count)
        }
        pendingSnippetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.triggerAmbiguityWindow, execute: work)
        Log.info(.hotKey, "Сниппет: триггер (\(trigger.count) симв.) неоднозначен, жду \(Self.triggerAmbiguityWindow) с")
    }

    private func cancelPendingSnippet() {
        pendingSnippetWork?.cancel()
        pendingSnippetWork = nil
    }

    /// Takes the operation lock synchronously, here in the tap — taking it later inside a
    /// Task left a window where another operation could start first. Returns false when busy.
    @discardableResult
    private func fireSnippet(_ snippet: Snippet, trigger: String, deleting count: Int,
                             separator: Character? = nil) -> Bool {
        guard let token = OperationGate.begin(.snippet) else { return false }
        // Re-entry guard: our own backspace/paste go through the same event tap.
        // Without clearing the buffer and the flag they would match the trigger again and loop the insert.
        isInsertingSnippet = true
        InputMonitor.shared.clearBuffer()
        InputMonitor.shared.suspend(for: 0.7)
        DispatchQueue.main.async {
            Task { @MainActor in
                // defer — otherwise on cancellation/exception in insertWithTriggerDelete the flag would
                // stay true forever, and handleRawEvent would swallow ALL user keystrokes (the keyboard
                // "dies" until the app restarts).
                defer { self.isInsertingSnippet = false }
                await SnippetService.shared.insertWithTriggerDelete(
                    snippet: snippet, triggerLength: count, separator: separator, holding: token)
            }
        }
        return true
    }

    // MARK: - Reacting to hotkey changes in settings

    @objc private func customHotKeyChanged(_ notification: Notification) {
        loadCombos()
        updateLayoutSwitchHotKey(combo: layoutSwitchCombo)
        updateErrorFixHotKey(combo: errorFixCombo)
        updateVoiceHotKey(combo: voiceToTextCombo)
        updateUndoHotKey(combo: undoCombo)
        updatePaletteHotKey(combo: paletteCombo)
        updateCheatsheetHotKey(combo: cheatsheetCombo)
        registerAppHotKeys()
        registerCustomHotKeys()
        registerSnippetHotKeys()
    }

    @objc private func customModulesChanged() {
        loadCustomModules()
        registerCustomHotKeys()
    }

    @objc private func snippetsChangedHandler() {
        loadSnippets()
        registerSnippetHotKeys()
    }

    private func matchesRaw(event: CGEvent, combo: KeyCombo) -> Bool {
        // System keys must be handled only via systemDefined events (otherwise they'd collide
        // with regular digit/letter keyCodes, as with the F7/F9 media keys).
        if combo.isSystemKey { return false }
        guard event.type == .keyDown else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        // Compare the key, not the code: the F3–F6 row arrives with two different codes from the
        // built-in and external keyboards (see KeyCodeEquivalents).
        guard KeyCodeEquivalents.same(keyCode, combo.keyCode) else { return false }
        
        let eventMods = normalizedModifiers(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
        let comboMods = normalizedModifiers(combo.modifiers)
        
        if comboMods.isEmpty {
            // For bare keys (no modifiers) skip the modifier check, so it fires even if the system
            // adds shift when typing a character (e.g. ~).
            return true
        }
        
        return eventMods == comboMods
    }
    
    /// Launching is delegated to the service: the hotkey manager is responsible for WHAT was
    /// pressed, not for how to open a folder or hide the active app.
    private func launchApp(_ shortcut: AppLaunchShortcut) {
        AppLauncherService.shared.launch(shortcut)
    }

    private struct SystemKeyInfo {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let isKeyDown: Bool
        let rawState: UInt16
        let isRepeat: Bool
    }
    
    private func systemKeyInfo(from event: CGEvent) -> SystemKeyInfo? {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == kNXSubtypeAuxControlButtons else { return nil }
        let data1 = nsEvent.data1
        let keyCode = UInt16((data1 & 0xffff0000) >> 16)
        let keyFlags = (data1 & 0x0000ffff)
        let keyState = (keyFlags & 0xff00) >> 8
        let isKeyDown = keyState != 0x0B // treat everything except an explicit keyUp as a press
        let isRepeat = (keyFlags & 0x1) != 0
        
        let eventMods = normalizedModifiers(nsEvent.modifierFlags)
        return SystemKeyInfo(keyCode: keyCode,
                             modifiers: eventMods,
                             isKeyDown: isKeyDown,
                             rawState: UInt16(keyState),
                             isRepeat: isRepeat)
    }
    
    private func matches(systemInfo: SystemKeyInfo, combo: KeyCombo) -> Bool {
        guard KeyCodeEquivalents.same(systemInfo.keyCode, combo.keyCode) else { return false }
        
        let comboMods = normalizedModifiers(combo.modifiers)
        if comboMods.isEmpty {
            return true
        }
        return systemInfo.modifiers == comboMods
    }
    
    private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .shift, .control])
    }
    
    /// Module master switch (on by default if the key doesn't exist yet).
    private func moduleEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// First-launch default combos: only the three main features, plus undo and the palette.
    ///
    /// One ⌥⌘ family: one modifier for the whole product, mnemonic letters. ⌥⌘V is deliberately
    /// NOT used for voice — in Finder it's "Move Item Here", and a global intercept would break
    /// regular file handling; ⌥⌘R (Record) is used instead.
    static let defaultHotKeys: [(key: String, combo: KeyCombo)] = [
        (SettingsKeys.layoutHotKey,        KeyCombo(keyCode: UInt16(kVK_ANSI_L), modifiers: [.command, .option])),
        (SettingsKeys.errorFixHotKey,      KeyCombo(keyCode: UInt16(kVK_ANSI_E), modifiers: [.command, .option])),
        (SettingsKeys.voiceHotKey,         KeyCombo(keyCode: UInt16(kVK_ANSI_R), modifiers: [.command, .option])),
        (SettingsKeys.undoHotKey,          KeyCombo(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command, .option])),
        (SettingsKeys.snippetPaletteHotKey, KeyCombo(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command, .option])),
        // Cheatsheet. "/" — the same place Slack and Notion keep it: the combo can be guessed
        // without reading docs.
        (SettingsKeys.cheatsheetHotKey,    KeyCombo(keyCode: UInt16(kVK_ANSI_Slash), modifiers: [.command, .option])),
    ]

    /// Seeds the defaults into `UserDefaults` ONCE per installation.
    ///
    /// Why seed instead of substituting a default "when there's no entry": a removed hotkey is
    /// also a missing entry, and substitution would bring it back on every launch. The user
    /// couldn't disable a combo at all.
    /// Reset all combos to defaults.
    ///
    /// Overwrite ALL keys, not just empty ones: the point of the action is to return the
    /// original state to someone confused by their assignments, and a "partial reset" would
    /// leave them in exactly the same confusion.
    func resetHotKeysToDefaults() {
        let defaults = UserDefaults.standard
        for (key, combo) in Self.defaultHotKeys {
            if let data = try? JSONEncoder().encode(combo) {
                defaults.set(data, forKey: key)
            }
        }
        Log.info(.hotKey, "Хоткеи сброшены к дефолтам")
        NotificationCenter.default.post(name: .customHotKeyChanged, object: nil)
    }

    private func seedDefaultHotKeysIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKeys.hotkeyDefaultsSeeded) else { return }
        for (key, combo) in Self.defaultHotKeys where defaults.data(forKey: key) == nil {
            if let data = try? JSONEncoder().encode(combo) {
                defaults.set(data, forKey: key)
            }
        }
        defaults.set(true, forKey: SettingsKeys.hotkeyDefaultsSeeded)
        Log.info(.hotKey, "HotKeyManager: засеяны дефолтные хоткеи первого запуска")
    }

    private func loadCombos() {
        seedDefaultHotKeysIfNeeded()
        // A module disabled by its master switch → combo nil: not registered and doesn't fire.
        // layout switch
        if moduleEnabled(SettingsKeys.layoutEnabled),
           let data = UserDefaults.standard.data(forKey: "customHotKey"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            layoutSwitchCombo = combo
        } else {
            layoutSwitchCombo = nil
        }

        // error fix
        if moduleEnabled(SettingsKeys.errorFixEnabled),
           let data = UserDefaults.standard.data(forKey: "customHotKeyErrorFix"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            errorFixCombo = combo
        } else {
            errorFixCombo = nil
        }

        // voice to text
        if moduleEnabled(SettingsKeys.voiceEnabled),
           let data = UserDefaults.standard.data(forKey: "customHotKeyVoiceToText"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            voiceToTextCombo = combo
        } else {
            voiceToTextCombo = nil
        }

        // Undo and the snippet palette. Their default comes from the same seeding above — there's
        // no separate substitution here anymore: two mechanisms for one concept would drift, and a
        // removed hotkey would come back for some and not for others.
        undoCombo = UserDefaults.standard.data(forKey: SettingsKeys.undoHotKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
        cheatsheetCombo = UserDefaults.standard.data(forKey: SettingsKeys.cheatsheetHotKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
        paletteCombo = UserDefaults.standard.data(forKey: SettingsKeys.snippetPaletteHotKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }

        // Launch targets — THROUGH THE STORE, not a raw decode. A second copy of the same read as
        // on the screen used to live here: both stopped understanding the data as soon as the
        // store wrote a schema envelope. App hotkeys then simply stopped registering — silently,
        // without a single sign on screen.
        appLaunchShortcuts = moduleEnabled(SettingsKeys.appLauncherEnabled)
            ? AppLauncherStore.shared.shortcuts
            : []
    }
    
    private static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command)  { result |= UInt32(cmdKey) }
        if flags.contains(.option)   { result |= UInt32(optionKey) }
        if flags.contains(.shift)    { result |= UInt32(shiftKey) }
        if flags.contains(.control)  { result |= UInt32(controlKey) }
        return result
    }
}

extension Notification.Name {
    /// Request to close the settings window. One exit, three ways to reach it: Esc, ⌘W and the close button.
    static let closeOnboardingWindow = Notification.Name("keyly.closeOnboardingWindow")

    /// The event tap health state changed. The listener raises the alarm menu bar icon and a
    /// banner in the window: a silently dead tap looks like "Keyly is broken", and the user
    /// doesn't know what to fix.
    static let eventTapHealthChanged = Notification.Name("keyly.eventTapHealthChanged")
}
