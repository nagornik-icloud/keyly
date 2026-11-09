import Foundation

/// Centralized UserDefaults keys — the single source of truth for all settings.
enum SettingsKeys {
    /// The first-run wizard is completed. It is shown ONCE.
    static let wizardCompleted = "wizardCompleted"
    static let layoutHotKey    = "customHotKey"
    static let errorFixHotKey  = "customHotKeyErrorFix"
    static let voiceHotKey     = "customHotKeyVoiceToText"
    /// Hotkey for undoing the last action. The feature MUST have a default: without it the
    /// destructive action is unreachable out of the box, and the menu remains the only way.
    static let undoHotKey      = "customHotKeyUndo"
    /// Snippet palette hotkey. It has a default for the same reason as undo:
    /// without it the palette exists but is unreachable.
    static let snippetPaletteHotKey = "customHotKeySnippetPalette"
    /// Cheatsheet of active shortcuts. A floating window above other windows: the product is all
    /// about hotkeys, and otherwise the only way to recall an assignment is to open the window and
    /// scroll through screens.
    static let cheatsheetHotKey = "customHotKeyCheatsheet"

    /// Whether the first-run default hotkeys have been seeded. Without this flag "default when no
    /// value is stored" would mean that a hotkey REMOVED by the user comes back by itself on the
    /// next launch — a setting that can't be turned off.
    /// The version in the key is bumped when a NEW shortcut is added to the defaults table:
    /// existing installs already have the flag set, and the new hotkey would otherwise never be seeded.
    static let hotkeyDefaultsSeeded = "hotkeyDefaults.seeded.v2"
    static let appShortcuts    = "appLaunchShortcuts"
    static let customModules   = "customAIModules"
    static let launchAtLogin   = "launchAtLogin"
    static let showDockIcon    = "showDockIcon"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showOnboarding  = "showOnboardingOnLaunch"
    /// Pause: all hotkeys and text features are turned off at once. It is persisted because
    /// people pause for a call or a screen share and walk away; resetting it on restart would
    /// turn on features they deliberately turned off.
    static let isPaused        = "app.isPaused"
    /// The version whose "what's new" has already been shown. A VERSION is stored, not a flag:
    /// a flag would have to be reset by hand on every release, and one day that would be forgotten.
    static let seenVersion     = "app.seenVersion"
    /// Starter content has been laid out. A separate flag rather than an "is the list empty" check:
    /// otherwise deleted examples would come back on every launch.
    static let starterContentSeeded = "app.starterContentSeeded"
    static let snippets        = "snippets"
    /// Text post-processing level — ONE for the whole product (voice and typo fixing).
    /// Replaced the pair of toggles `voiceFormatParagraphs` + `voicePolishCorrections`,
    /// whose captions didn't match the prompts actually invoked.
    static let textPolishLevel = "text.polishLevel"
    /// Typo fixing strictness — its OWN key. Sharing `textPolishLevel` with voice
    /// meant that switching it on one screen silently changed the behavior of another module,
    /// while the typo module itself didn't read it at all.
    static let errorFixLevel = "errorFix.level"

    /// Recognition method: local / cloud all at once / cloud live.
    /// Replaced the pair `voiceEngine` + `voiceRealtimeMode`, which described one axis
    /// but were two independent settings and conflicted.
    static let voiceRecognitionMode = "voiceToText.recognitionMode"
    /// UID of the selected microphone. Empty = system input. We store the UID, not the
    /// numeric AudioDeviceID: that one is reassigned every time the device is connected.
    static let voiceInputDeviceUID = "voiceToText.inputDeviceUID"
    /// The RECOGNITION model for cloud modes (selectable). Stored separately from the text
    /// post-processing model — these are different models, and a shared key already led to
    /// transcription being sent as a chat request.
    static let voiceTranscriptionModel = "voiceToText.transcriptionModel"

    /// Recording indicator placement.
    static let voiceIndicatorPlacement = "voiceToText.indicator.placement"

    /// Dictation language: auto ru+en / ru only / en only.
    static let voiceLanguage = "voiceToText.language"

    static let voiceEngine = "voiceToText.engine"
    static let voiceFormatParagraphs = "voiceToText.formatParagraphs"
    static let voiceRealtimeMode     = "voiceToText.realtimeMode"
    static let voicePolishCorrections = "voiceToText.polishCorrections"
    static let voiceIndicatorShowTimer = "voiceToText.indicator.showTimer"
    /// Leave dictated text on the clipboard after pasting (default on: if focus moved away,
    /// the text is not lost). Off — the clipboard is restored to what it held before.
    static let voiceKeepInClipboard = "voiceToText.keepInClipboard"

    // Master on/off switch for built-in modules (on by default if no value is stored).
    static let layoutEnabled      = "module.layout.enabled"
    static let errorFixEnabled    = "module.errorFix.enabled"
    static let voiceEnabled       = "module.voice.enabled"
    static let appLauncherEnabled = "module.appLauncher.enabled"
}
