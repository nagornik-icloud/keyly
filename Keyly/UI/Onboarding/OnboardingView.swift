import SwiftUI
import AppKit
import Combine

enum ModuleKind: Hashable, CaseIterable {
    /// Stable key for accessibility identifiers — derived from the type, not the label.
    var axKey: String {
        switch self {
        case .layoutSwitch: return "layout"
        case .errorFix:     return "errorFix"
        case .voiceToText:  return "voice"
        case .appLauncher:  return "appLauncher"
        }
    }

    case layoutSwitch
    case errorFix
    case voiceToText
    case appLauncher

    /// Short names are not about looks: in the 220pt sidebar "Keyboard layout switching" did
    /// not fit and was truncated with an ellipsis — the only one of four, so it read not as a
    /// long name but as breakage on the very first row.
    /// "Typo fixing", not "error fixing": the module fixes typos and punctuation, not errors
    /// in general, and the label must not promise more than the prompt does.
    var title: String {
        switch self {
        case .layoutSwitch: return "module.layoutSwitch.title".loc
        case .errorFix: return "module.errorFix.title".loc
        case .voiceToText: return "module.voiceToText.title".loc
        case .appLauncher: return "module.appLauncher.title".loc
        }
    }

    var subtitle: String {
        switch self {
        case .layoutSwitch: return "module.layoutSwitch.subtitle".loc
        case .errorFix: return "module.errorFix.subtitle".loc
        case .voiceToText: return "module.voiceToText.subtitle".loc
        case .appLauncher: return "module.appLauncher.subtitle".loc
        }
    }

    var icon: String {
        switch self {
        case .layoutSwitch: return "keyboard"
        case .errorFix: return "wand.and.stars"
        case .voiceToText: return "mic.fill"
        case .appLauncher: return "app.badge"
        }
    }

    /// One accent for the whole app — lime. No per-module rainbow.
    var accent: Color { Theme.Colors.accent }
}

final class OnboardingViewModel: ObservableObject {
    @Published var selectedModule: ModuleKind?
    @Published var openSettings: Bool
    /// DEBUG QA screenshots: explicit start screen without env (see ScreenSnapshotExporter).
    var initialSelection: NavItem? = nil

    init(selectedModule: ModuleKind? = nil, openSettings: Bool = false) {
        self.selectedModule = selectedModule
        self.openSettings = openSettings
    }
}

enum NavItem: Hashable {
    case overview
    case module(ModuleKind)
    case settings
    case custom(UUID)
    case snippets

    /// Stable key for accessibility identifiers.
    ///
    /// Derived from the TYPE, not the on-screen label: the label is copy, it changes,
    /// and UI automation looking up a control by a Russian word would break on a text edit.
    /// The driver (`scripts/ax-driver`) addresses controls by exactly these keys.
    var axKey: String {
        switch self {
        case .overview:          return "overview"
        case .module(let kind):  return "module.\(kind.axKey)"
        case .settings:          return "settings"
        case .snippets:          return "snippets"
        case .custom(let id):    return "custom.\(id.uuidString)"
        }
    }
}

struct OnboardingView: View {
    @AppStorage(SettingsKeys.launchAtLogin) var launchAtLogin: Bool = false
    @AppStorage(SettingsKeys.layoutHotKey) var customHotKeyData: Data?
    @AppStorage(SettingsKeys.errorFixHotKey) var customHotKeyErrorFixData: Data?
    @AppStorage(SettingsKeys.voiceHotKey) var customHotKeyVoiceData: Data?
    // Three GLOBAL combos: undo, snippet palette, cheatsheet. They are registered from
    // the first launch (HotKeyManager seeds ⌥⌘Z / ⌥⌘S / ⌥⌘/), but there were NO fields
    // for them — the only ways to change them were "Reset hotkeys" or a file import. Meanwhile
    // `openHotKeySource` already promised that "undo and palette are configured right here" and
    // expanded "Advanced", where nothing appeared.
    @AppStorage(SettingsKeys.undoHotKey) var customHotKeyUndoData: Data?
    @AppStorage(SettingsKeys.snippetPaletteHotKey) var customHotKeyPaletteData: Data?
    @AppStorage(SettingsKeys.cheatsheetHotKey) var customHotKeyCheatsheetData: Data?
    @AppStorage(SettingsKeys.showMenuBarIcon) var showMenuBarIcon: Bool = true
    @AppStorage(SettingsKeys.showDockIcon) var showDockIcon: Bool = true
    @AppStorage(SettingsKeys.voiceIndicatorPlacement) var voiceIndicatorPlacement: String = VoiceIndicatorPlacement.default.rawValue
    @AppStorage(SettingsKeys.voiceLanguage) var voiceLanguage: String = VoiceLanguage.default.rawValue
    @AppStorage(SettingsKeys.voiceIndicatorShowTimer) var voiceIndicatorShowTimer: Bool = true
    @AppStorage(SettingsKeys.voiceKeepInClipboard) var voiceKeepInClipboard: Bool = true
    @AppStorage(SettingsKeys.layoutEnabled) var layoutModuleEnabled: Bool = true
    @AppStorage(SettingsKeys.errorFixEnabled) var errorFixModuleEnabled: Bool = true
    @AppStorage(SettingsKeys.voiceEnabled) var voiceModuleEnabled: Bool = true
    @AppStorage(SettingsKeys.appLauncherEnabled) var appLauncherModuleEnabled: Bool = true

    @ObservedObject var model: OnboardingViewModel
    var onClose: () -> Void = {}
    var onSizeChange: ((CGSize) -> Void)? = nil

    @State var selection: NavItem = .overview
    @State var hasAccessibilityAccess: Bool = AccessibilityPermission.isTrusted
    @State var hasMicrophoneAccess: Bool = MicrophonePermission.isAuthorized
    /// The third system permission — in `@State`, like the other two.
    ///
    /// The first version read `InputMonitoringPermission.isGranted` directly in a computed
    /// property. SwiftUI does not observe system permissions: the "needs setup" row would keep
    /// hanging AFTER access was granted, until the screen redrew for some other reason. So the
    /// app would lie the other way — now about something not fixed.
    @State var hasInputMonitoring: Bool = InputMonitoringPermission.isGranted
    @StateObject var apiKeyStore = APIKeyStore.shared
    /// Observe the language: a change must redraw the screen IMMEDIATELY, without restarting the app.
    @StateObject var languageManager = LanguageManager.shared
    @StateObject var statsStore = UsageStatsStore.shared
    @State var customModules: [CustomAIModule] = CustomModuleStore.load()
    @State var showAddKeySheet = false
    /// Key rotation: id of the key being replaced + new value.
    @State var rotatingKeyId: UUID?
    @State var rotatedValue: String = ""
    @State var newKeyProvider: APIProvider = .openai
    @State var newKeyName: String = ""
    @State var newKeyValue: String = ""
    @State var lastReportedSize: CGSize = .zero
    @State var appLaunchShortcuts: [AppLaunchShortcut] = []
    /// Stats reset confirmation — an irreversible action next to everyday ones.
    @State var showStatsResetConfirm = false
    @State var snippets: [Snippet] = []
    @State var expandedSnippetId: UUID?
    /// The card being dragged: the original is dimmed while dragging.
    @State var draggingSnippetId: UUID?
    /// Why the last entered trigger was rejected. Empty — accepted.
    @State var triggerRejection: String?
    /// The launch target row being dragged.
    @State var draggingShortcutId: UUID?
    /// Draft of the "Paste a link" field on the launcher screen.
    @State var launcherLinkDraft: String = ""
    /// Which dashboard sections are fully expanded.
    @State var expandedOverviewSections: Set<String> = []
    /// Snippet search string.
    @State var snippetQuery: String = ""
    /// App pause — the window must show it.
    @State var isPaused: Bool = AppPause.isPaused
    /// Show the self-lockout warning.
    @State var menuBarHideWarning = false
    /// The "my modules" sidebar item being dragged.
    @State var draggingModuleId: UUID?
    /// The version whose "What's new" the user has already seen.
    @AppStorage(SettingsKeys.seenVersion) var seenVersion: String = ""
    @State var showWhatsNew = false
    /// Per-session screen state: the selected item and the search query survive leaving to
    /// another screen and coming back. NOT kept between launches — someone coming back
    /// tomorrow expects a clean screen, not yesterday's filter.
    @State var sessionState = ScreenSessionState()
    /// Whether the "My modules" group and its search are expanded (only from nine modules on).
    @State var myModulesExpanded = true
    @State var myModulesQuery = ""
    /// "Advanced" is COLLAPSED on every screen opening — @State, not @AppStorage: a remembered
    /// "expanded" state would expose dangerous actions to an accidental click. Except during capture.
    ///
    /// A collapsed section meant its contents made it into NO capture: the three global hotkey
    /// fields, backup, reset and wizard replay were a blind spot.
    /// Only capture (`qa-capture.sh`) sets `KEYLY_QA_ADVANCED=1`; this state does not leak into
    /// the app: a normal launch reads an env variable that is absent and gets false.
    @State var advancedExpanded = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KEYLY_QA_ADVANCED"] == "1"
        #else
        return false
        #endif
    }()
    @State var showHotkeyResetConfirm = false
    @State var tipsExpanded: Bool = true  // "How it works" — expanded by default
    @State var snippetBeforeEdit: [UUID: Snippet] = [:]
    @State var unsavedSnippetIds: Set<UUID> = []
    /// Hotkey assignment conflict. Not an alert: a modal took the user away from the field,
    /// showed "taken" and left them to sort it out — the previous holder had to be hunted
    /// down by hand among six assignment places. Now the message sits UNDER the field where
    /// the user just pressed keys, and offers to take the combo over.
    ///
    /// `KEYLY_QA_CONFLICT=1` creates it right when the screen opens — otherwise the state
    /// made it into NO capture: a conflict arises only from a real key press, which
    /// capture does not perform, so changes to the conflict banner could not be seen at all.
    @State var hotKeyConflict: HotKeyConflict? = {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["KEYLY_QA_CONFLICT"] == "1" else { return nil }
        return HotKeyConflict(fieldID: HotKeyFieldID.errorFix,
                              owner: .module(.voiceToText),
                              apply: {})
        #else
        return nil
        #endif
    }()
    @State var validationStatus: [UUID: ValidationState] = [:]
    /// The "Microphone, overlay, language" section is collapsed. Capture also needs the expanded
    /// view: its contents made it into NO capture, and issues with a dead microphone picker
    /// could not be verified three times in a row — in the end the source had to be patched by
    /// hand just to see the screen.
    @State var showVoiceAdvanced: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["KEYLY_QA_VOICE_ADVANCED"] == "1"
        #else
        return false
        #endif
    }()

    /// Close cross in the top-right corner.
    ///
    /// The window has no traffic-light buttons, so until now it could only be closed with
    /// Esc or ⌘W — someone not knowing the shortcut had no way at all. The button performs
    /// the same action as the keys: introduces nothing new, just makes the existing exit
    /// visible.
    private var closeButton: some View {
        Button {
            NotificationCenter.default.post(name: .closeOnboardingWindow, object: nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.fgMuted)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.Colors.surfaceHover))
                .overlay(Circle().stroke(Theme.Colors.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("common.close".loc)
        .accessibilityLabel("common.close".loc)
        .padding(Theme.Space.m)
        // TOP OF THE WINDOW, not the safe area. A `.fullSizeContentView` window draws to the
        // very edge, but SwiftUI layout by default insets from the title bar strip —
        // and the cross sat 12pt from the right but ~40pt from the top. Insets match only
        // when measured from the same edge.
        .ignoresSafeArea(edges: .top)
    }

    let accentColor = Theme.Colors.accent
    let dangerColor = Theme.Colors.danger

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 220, maxWidth: 260)
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 260)
        } detail: {
            ZStack {
                Theme.Colors.bg
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    pauseBanner
                    // The scroll goes TO THE VERY EDGE of the window, and the padding lives INSIDE it.
                    //
                    // Two earlier attempts missed the edge. The first put the gradient on the outer
                    // container — above the clipping line, where there was nothing to clip. The second
                    // moved it onto the scroll view, but the scroll view itself sat inside the 24pt
                    // padding: a solid black strip remained on top, and the gradient started BELOW it
                    // and overlapped the content. The goal was explicit: remove the strip and move the
                    // gradient to the very edge.
                    //
                    // `contentMargins` gives exactly that: content is inset by 24pt at rest, but when
                    // scrolled it slides UNDER the edge — where the gradient fades it out.
                    detailContent
                        .contentMargins(.vertical, Theme.Space.xl, for: .scrollContent)
                        .padding(.horizontal, Theme.Space.xl)
                        .contentEdgeFade()
                }
                // The app has no scroll bars: on the right they were noise on every
                // screen.
                //
                // The edge fade CAME BACK on explicit request — but differently from
                // before: back then it was "a foreign black bar covering content",
                // now it is a soft gradient only where content actually continues.
                // The recipe lives in `ContentEdgeFade`.
                .scrollIndicators(.hidden)
            }
            .overlay(alignment: .topTrailing) { closeButton }
            .animation(KeylyMotion.emphasis, value: selection)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.accent)
        .onReceive(NotificationCenter.default.publisher(for: AppPause.changed)) { _ in
            isPaused = AppPause.isPaused
        }
        // Entry from the palette: open the snippets section and expand the right one,
        // or create a new one — both paths must bring the user to where they see the result.
        .onReceive(NotificationCenter.default.publisher(for: .openSnippetInEditor)) { note in
            snippets = SnippetStore.load()
            snippetQuery = ""
            selection = .snippets
            if let id = note.object as? UUID {
                expandedSnippetId = id
            } else {
                let created = Snippet(content: "")
                snippets.append(created)
                persistSnippets()
                expandedSnippetId = created.id
            }
        }
        .onAppear {
            isPaused = AppPause.isPaused
            // Decide ONCE when the window opens, not in the view body: otherwise the
            // card would flicker on every redraw.
            let version = appVersionString()
            if seenVersion.isEmpty {
                // First launch: the user is greeted by the wizard; "What's new" has nothing to compare against.
                seenVersion = WhatsNew.initialSeenVersion(currentVersion: version)
            } else {
                showWhatsNew = WhatsNew.shouldShow(currentVersion: version, seenVersion: seenVersion)
            }
            reloadAppLaunchShortcutsFromDefaults()
            hasAccessibilityAccess = AccessibilityPermission.isTrusted
            hasMicrophoneAccess = MicrophonePermission.isAuthorized
            hasInputMonitoring = InputMonitoringPermission.isGranted
            customModules = CustomModuleStore.load()
            snippets = SnippetStore.load()
            if let initial = model.initialSelection {
                selection = initial
            } else if model.openSettings {
                selection = .settings
                model.openSettings = false
            } else if let module = model.selectedModule {
                selection = .module(module)
            }
            #if DEBUG
            switch ProcessInfo.processInfo.environment["KEYLY_SCREEN"] {
            case "snippets": selection = .snippets
            case "custom":   if let first = customModules.first { selection = .custom(first.id) }
            default: break
            }
            #endif
            syncValidationStatus()
            // Validate keys RIGHT AWAY. The network check used to run only on switching
            // to "Settings", while the start screen is "Overview": the green "all set"
            // pill showed with a known-broken key until the user looked where that fact
            // is computed. A readiness indicator cannot depend on whether the user opened
            // another screen.
            validateAllStoredKeys(forceReset: false)
        }
        .onReceive(
            Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
        ) { _ in
            let trusted = AccessibilityPermission.isTrusted
            let micGranted = MicrophonePermission.isAuthorized
            let inputMonitoring = InputMonitoringPermission.isGranted
            var shouldReturnToOverview = false
            if inputMonitoring != hasInputMonitoring {
                hasInputMonitoring = inputMonitoring
                if !inputMonitoring { shouldReturnToOverview = true }
            }
            if trusted != hasAccessibilityAccess {
                hasAccessibilityAccess = trusted
                if !trusted { shouldReturnToOverview = true }
            }
            if micGranted != hasMicrophoneAccess {
                hasMicrophoneAccess = micGranted
                if !micGranted { shouldReturnToOverview = true }
            }
            if shouldReturnToOverview { selection = .overview }
        }
        .onChange(of: model.selectedModule) { _, newValue in
            if let module = newValue {
                selection = .module(module)
            } else if !model.openSettings {
                selection = .overview
            }
        }
        .onChange(of: customModules) { _, modules in
            if case .custom(let id) = selection, modules.first(where: { $0.id == id }) == nil {
                selection = .overview
            }
        }
        .onChange(of: model.openSettings) { _, newValue in
            if newValue {
                selection = .settings
                model.openSettings = false
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .settings {
                validateAllStoredKeys(forceReset: true)
            }
            // Leaving a screen — remember what was on it; coming back — restore it.
            // Otherwise someone who popped into settings for a key loses their search and
            // the expanded card and can't remember what they were typing.
            if sessionState.lastSelection == .snippets {
                sessionState.snippetQuery = snippetQuery
                sessionState.expandedSnippetId = expandedSnippetId
            }
            if newValue == .snippets {
                snippetQuery = sessionState.snippetQuery
                expandedSnippetId = sessionState.expandedSnippetId
            }
            sessionState.lastSelection = newValue
        }
        .onChange(of: apiKeyStore.keys) {
            syncValidationStatus()
        }
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .onAppear { reportSizeIfNeeded(geo.size) }
                    .onChange(of: geo.size) { _, newValue in reportSizeIfNeeded(newValue) }
            }
        )
        .overlay(alignment: .center) {
            if !hasAccessibilityAccess || !hasMicrophoneAccess {
                ZStack {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea()
                        .blur(radius: 2)
                        .overlay(Color.black.opacity(0.25))
                        .allowsHitTesting(true)

                    VStack(spacing: 18) {
                        if !hasAccessibilityAccess {
                            permissionCard(
                                icon: "lock.shield",
                                title: "permission.ax.title".loc,
                                message: "permission.ax.message".loc,
                                tint: dangerColor
                            ) {
                                AccessibilityPermission.openAccessibilitySettings()
                                _ = AccessibilityPermission.ensurePermission(prompt: true)
                            }
                        }
                        if !hasMicrophoneAccess {
                            permissionCard(
                                icon: "mic.fill",
                                title: "permission.mic.title".loc,
                                message: "permission.mic.message".loc,
                                tint: Theme.Colors.warning
                            ) {
                                MicrophonePermission.ensurePermission(prompt: true) { granted in
                                    hasMicrophoneAccess = granted
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddKeySheet) {
            addKeySheet
                .frame(minWidth: 420)
        }
        .sheet(isPresented: Binding(
            get: { rotatingKeyId != nil },
            set: { if !$0 { rotatingKeyId = nil } }
        )) {
            rotateKeySheet
        }
    }

    // MARK: - Sidebar

    /// The sidebar uses an EXPLICIT layout, not `List`.
    ///
    /// Why not `List`. Three reasons converge:
    /// 1. the system source list puts a vibrancy material underneath — the sidebar stood out
    ///    in macOS gray from the flat monochrome design and did not render in QA captures;
    /// 2. in the AX tree a `List` row looks like `AXRow → AXCell → AXStaticText`, and SwiftUI
    ///    collapses any content accessibility modifiers into the cell. Measured with the driver:
    ///    after adding `.accessibilityIdentifier` there were ZERO addressable nodes, i.e.
    ///    UI automation was impossible by construction;
    /// 3. `List` imposed its own column width: 300pt instead of the intended 220.
    /// The same info the colored dot and counter carry — in words for the screen reader.
    /// Empty if the item has nothing to say beyond its title.
    func sidebarStateDescription(for item: NavItem) -> String {
        switch item {
        case .module(let kind):
            return moduleAttention(kind).labelKey?.loc ?? ""
        case .custom(let id):
            guard let module = customModules.first(where: { $0.id == id }) else { return "" }
            let attention = ModuleAttention.resolve(
                isEnabled: module.isEnabled,
                hasHotKey: module.hotKey != nil,
                needsKey: true,
                hasKey: apiKeyStore.entry(for: apiKeyStore.currentSelection(
                    for: .customModule(module.id))) != nil)
            return attention.labelKey?.loc ?? ""
        case .snippets:
            return snippets.isEmpty ? "" : String(snippets.count)
        case .overview, .settings:
            return ""
        }
    }

    /// Warning dot on a sidebar item.
    ///
    /// Color DISTINGUISHES states, the caption names them: relying on color alone is not
    /// allowed — not everyone can tell colors apart, and the tooltip needs text anyway.
    @ViewBuilder
    func attentionDot(_ attention: ModuleAttention) -> some View {
        if let labelKey = attention.labelKey {
            Circle()
                .fill(attention == .disabled ? Theme.Colors.danger : Theme.Colors.warning)
                .frame(width: 6, height: 6)
                .help(labelKey.loc)
        }
    }

    /// Pause banner. A pause visible only in the menu bar is useless: the user opens the
    /// window, sees enabled toggles and working hotkey chips — and doesn't understand why
    /// nothing fires.
    @ViewBuilder
    var pauseBanner: some View {
        if isPaused {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.warning)
                Text("window.paused".loc)
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Colors.fg)
                Spacer(minLength: Theme.Space.m)
                Button("menu.resume".loc) {
                    AppPause.isPaused = false
                    isPaused = false
                }
                .buttonStyle(KeylySecondaryButtonStyle())
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.Colors.warning.opacity(0.12))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Colors.warning.opacity(0.35)).frame(height: 1)
            }
        }
    }

    var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
            // No section label: it would repeat the name of the only item.
            sidebarRow(.overview, "sidebar.overview".loc, "rectangle.grid.2x2") { EmptyView() }

            sidebarHeader("sidebar.modules".loc)
            Group {
                ForEach(ModuleKind.allCases, id: \.self) { module in
                    sidebarRow(.module(module), module.title, module.icon) {
                        // Two DIFFERENT states — two different colors and two different captions.
                        // Red: disabled on purpose.
                        // Orange: enabled, but cannot work.
                        attentionDot(moduleAttention(module))
                    }
                }
            }

            if !customModules.isEmpty {
                // From nine modules on the group gets a counter, collapsing and search:
                // a flat list of twenty items crowds everything else out of the sidebar,
                // and "Snippets" and "Settings" slide below the fold.
                if customModules.count > 8 {
                    myModulesHeaderWithControls
                    if myModulesExpanded, !myModulesQuery.isEmpty {
                        Text("sidebar.myModules.found".loc(visibleCustomModules.count))
                            .font(Theme.Typography.mono(9))
                            .foregroundStyle(Theme.Colors.fgDim)
                            .padding(.horizontal, 14)
                    }
                } else {
                    sidebarHeader("sidebar.myModules".loc)
                }
                // The order is user-defined and changed by dragging: by default it is
                // creation order, but people group modules by their own logic, not by
                // the date they created them.
                ForEach(Array(visibleCustomModules.enumerated()), id: \.element.id) { index, module in
                    sidebarRow(.custom(module.id), module.name, "sparkles") {
                        // A custom module always needs a key — it is a model request by definition.
                        attentionDot(ModuleAttention.resolve(
                            isEnabled: module.isEnabled,
                            hasHotKey: module.hotKey != nil,
                            needsKey: true,
                            hasKey: apiKeyStore.entry(for: apiKeyStore.currentSelection(
                                for: .customModule(module.id))) != nil))
                    }
                    .keylyReorderTarget(index: index,
                                        id: module.id,
                                        items: $customModules,
                                        draggingId: $draggingModuleId,
                                        onReorder: persistCustomModules)
                    .keylyDragSource(id: module.id, draggingId: $draggingModuleId)
                }
            }

            Button {
                    let newModule = addCustomModule()
                    selection = .custom(newModule.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        Text("sidebar.addModule".loc).font(.system(size: 13, weight: .regular))
                        Spacer()
                    }
                    // A quiet navigation action row (fgMuted), not a loud lime button —
                    // the accent stays rare, and the button fits into the sidebar list.
                    .foregroundStyle(Theme.Colors.fgMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
            .buttonStyle(.plain)
            .accessibilityIdentifier("keyly.sidebar.addModule")

            // There are NO "SNIPPETS" and "SETTINGS" headers here: each would sit above
            // a SINGLE item with the same name — the word read twice in a row, the user
            // expected a group under the header that does not exist, and two column rows were wasted.
            // By the same rule "Overview" above is not labeled either.
            Spacer().frame(height: Theme.Space.s)
            sidebarRow(.snippets, "sidebar.snippets".loc, "text.badge.plus") {
                if !snippets.isEmpty { CountBadge(count: snippets.count) }
            }
            sidebarRow(.settings, "sidebar.settings".loc, "gearshape") { EmptyView() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.bg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.Colors.border).frame(width: 1)
        }
        .environment(\.colorScheme, .dark)
        // Top inset for the native traffic-light buttons (top-left).
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 22) }
    }

    /// "My modules" header with counter, collapsing and search.
    var myModulesHeaderWithControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { myModulesExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: myModulesExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("sidebar.myModules".loc.uppercased())
                        .font(Theme.Typography.mono(10, .semibold))
                        .tracking(1.0)
                    Spacer(minLength: 6)
                    CountBadge(count: customModules.count)
                }
                .foregroundStyle(Theme.Colors.fgDim)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if myModulesExpanded {
                TextField("sidebar.myModules.search".loc, text: $myModulesQuery)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.caption)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .fill(Theme.Colors.surfaceHover)
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, Theme.Space.s)
    }

    /// Which modules to show: a collapsed group shows none, search filters by name.
    /// The list is NOT reordered — otherwise dragging would change the order among the
    /// visible ones while a different order got saved (same class as in snippets).
    var visibleCustomModules: [CustomAIModule] {
        guard customModules.count > 8 else { return customModules }
        guard myModulesExpanded else { return [] }
        let query = myModulesQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return customModules }
        return customModules.filter { $0.name.lowercased().contains(query) }
    }

    func sidebarHeader(_ text: String) -> some View {
        // Mirror the row insets (listRowInsets leading 6 + .padding 8 = 14) so the left
        // edge of the header lines up with the item icon. The header used to take the
        // default header inset and ended up left of the items.
        Text(text.uppercased())
            .font(Theme.Typography.mono(10, .semibold))
            .tracking(1.0)
            .foregroundStyle(Theme.Colors.fgDim)
            .textCase(nil)
            .padding(.horizontal, 8)
            .padding(.top, Theme.Space.m)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
    }

    @ViewBuilder
    func sidebarRow<Trailing: View>(_ item: NavItem, _ title: String, _ icon: String,
                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        let isSel = selection == item
        // A REAL button, not an HStack with `.onTapGesture`. A gesture is not exposed to
        // Accessibility as an action: the node has no `AXPress`, and automation clicked "into
        // the void" — the driver reported a successful press while no navigation happened.
        // That cannot be told apart from broken navigation by a screenshot, so all automated
        // walkthroughs of the app were blocked.
        Button {
            withAnimation(KeylyMotion.standard) { selection = item }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSel ? Theme.Colors.fg : Theme.Colors.fgMuted)
                Text(title)
                    // Weight does NOT change on selection. A semibold line is wider than a regular
                    // one, and in the 220pt sidebar the only long name — "Typo fixing" — fit in
                    // regular but got truncated in semibold: the item broke exactly when it was
                    // clicked, and it looked like breakage, not like selection.
                    //
                    // "Where am I" is carried by three other signals, none of which touch text metrics:
                    // color (fg vs fgMuted), the `accentSoft` fill and the accent bar on the left.
                    .font(.system(size: 13))
                    .foregroundStyle(isSel ? Theme.Colors.fg : Theme.Colors.fgMuted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The system focus ring stretched across the WHOLE row as a bright olive frame and
        // stayed on "Overview" while another section was selected: frame on one item,
        // selection on another. It is invisible in offscreen renders (the window is not
        // key), so the defect survived until a real run.
        .focusEffectDisabled()
        // Addressable by UI automation: the key is derived from the TYPE (`axKey`), not from
        // the label — the label is copy, it changes, and automation would break on a text
        // edit. This works only because the sidebar is no longer a `List`: inside a list
        // SwiftUI collapsed these modifiers into the table cell.
        .accessibilityIdentifier("keyly.sidebar.\(item.axKey)")
        // An explicit label REPLACES all the button's content, so the warning dot
        // ("disabled" / "enabled but cannot work") and the snippet counter never reached
        // VoiceOver. The "don't rely on color alone" rule held for the eyes and was
        // broken for the screen reader. The state goes into
        // `accessibilityValue` — the same text the tooltip shows.
        .accessibilityLabel(title)
        .accessibilityValue(sidebarStateDescription(for: item))
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isSel ? Theme.Colors.accentSoft : Color.clear)
        )
        // 2.5px accent bar on the left of the selected item: a .07 fill on its own
        // is too quiet to answer "where am I".
        .overlay(alignment: .leading) {
            if isSel {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.Colors.accent)
                    .frame(width: 2.5)
                    .padding(.vertical, 3)
                    .offset(x: -6)
            }
        }
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Detail

    @ViewBuilder
    var detailContent: some View {
        switch selection {
        case .overview:
            overviewContent
        case .module(let module):
            moduleDetail(module)
        case .custom(let id):
            customModuleDetail(id: id)
        case .snippets:
            snippetsContent
        case .settings:
            settingsContent
        }
    }
}

#Preview {
    OnboardingView(model: OnboardingViewModel())
}
