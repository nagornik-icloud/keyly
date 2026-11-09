#if DEBUG
import AppKit
import Carbon.HIToolbox

/// Neutral demo data for public screenshots (README, release notes).
///
/// Switched on by `KEYLY_DEMO=1` together with a capture variable (`KEYLY_LIVESHOT=…`).
/// Live frames used to show the developer's own module names and usage numbers, and every
/// capture run read from — and twice wrote into — the user's real settings. Demo content fixes
/// both: it is written ONLY into the Debug build's own domain (`app.keyly.Keyly.debug`), and
/// demo API keys exist only in memory.
@MainActor
enum DemoContent {

    /// Never true in the build that owns real data: the release id is refused outright, so a
    /// stray `KEYLY_DEMO` can't overwrite anything the user configured.
    /// Also requires a capture run: a full launch with demo keys and faked permissions would
    /// register hotkeys and could send real selected text to a provider.
    nonisolated static var isActive: Bool {
        let env = ProcessInfo.processInfo.environment
        let capturing = !(env["KEYLY_LIVESHOT"] ?? "").isEmpty || env["KEYLY_QA_SNAPSHOT"] == "1"
        return env["KEYLY_DEMO"] == "1" && capturing && !AppIdentity.isReleaseIdentity
    }

    private static let openAIKeyID = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000001")!
    private static let geminiKeyID = UUID(uuidString: "D0D0D0D0-0000-4000-8000-000000000002")!

    /// Placeholder values: capture runs make no network calls, and these are obviously not
    /// real keys if they ever show up on screen.
    static let apiKeys: [APIKeyEntry] = [
        APIKeyEntry(id: openAIKeyID, name: "Personal", value: "demo-key-openai-0000",
                    provider: .openai, isBuiltin: false, model: nil),
        APIKeyEntry(id: geminiKeyID, name: "Work", value: "demo-key-gemini-0000",
                    provider: .gemini, isBuiltin: false, model: nil),
    ]

    /// Overwrites the Debug domain with the demo set on every run, so frames are reproducible.
    static func seedIfActive(defaults: UserDefaults = .standard) {
        guard isActive else { return }
        let combo = { (key: Int, mods: NSEvent.ModifierFlags) in
            KeyCombo(keyCode: UInt16(key), modifiers: mods)
        }

        for (key, value) in HotKeyManager.defaultHotKeys {
            defaults.set(try? JSONEncoder().encode(value), forKey: key)
        }
        defaults.set(true, forKey: SettingsKeys.hotkeyDefaultsSeeded)

        _ = CustomModuleStore.save([
            CustomAIModule(name: "Translate to English",
                           prompt: "Translate the text into natural, fluent English. Keep the formatting.",
                           hotKey: combo(kVK_ANSI_E, [.control, .option]),
                           textSource: .selected, output: .insert),
            CustomAIModule(name: "Make it polite",
                           prompt: "Rewrite the message so it sounds friendly and professional.",
                           hotKey: combo(kVK_ANSI_P, [.control, .option]),
                           textSource: .selected, output: .insert),
            CustomAIModule(name: "Summarize",
                           prompt: "Summarize the text in three short bullet points.",
                           hotKey: combo(kVK_ANSI_M, [.control, .option]),
                           textSource: .selected, output: .panel),
        ])

        _ = SnippetStore.save([
            Snippet(name: "Email", content: "hello@example.com", triggers: ["@@mail"]),
            Snippet(name: "Greeting", content: "Hi! Thanks for reaching out — I'll get back to you today.",
                    triggers: ["@@hi"]),
            Snippet(name: "Address", content: "221B Baker Street, London",
                    hotKey: combo(kVK_ANSI_A, [.control, .option, .command])),
            Snippet(name: "Signature", content: "Best regards,\nAlex", triggers: [";sig"],
                    triggerMode: .immediate),
        ])

        AppLauncherStore.shared.replace(all: [
            AppLaunchShortcut(appPath: "/Applications/Safari.app",
                              keyCombo: combo(kVK_ANSI_S, [.control, .option])),
            AppLaunchShortcut(appPath: "/System/Applications/Notes.app",
                              keyCombo: combo(kVK_ANSI_N, [.control, .option])),
            AppLaunchShortcut(appPath: "/System/Applications/Utilities/Terminal.app",
                              keyCombo: combo(kVK_ANSI_T, [.control, .option])),
        ])

        let selection = APIKeySelection(provider: .openai, keyId: openAIKeyID,
                                        model: APIProvider.openai.defaultModel)
        let encoded = try? JSONEncoder().encode(selection)
        defaults.set(encoded, forKey: "apiKeys.selected.errorFix")
        defaults.set(encoded, forKey: "apiKeys.selected.voiceToText")
        defaults.removeObject(forKey: "apiKeys.selected.customModules")
        let checked = Date().addingTimeInterval(-2 * 86_400).timeIntervalSince1970
        defaults.set([openAIKeyID.uuidString: checked, geminiKeyID.uuidString: checked],
                     forKey: "apiKeys.lastCheck")

        defaults.set(stats(), forKey: "usageStats")
        defaults.set("cloudBatch", forKey: SettingsKeys.voiceRecognitionMode)
        defaults.set("tidy", forKey: SettingsKeys.textPolishLevel)
        defaults.set(true, forKey: SettingsKeys.wizardCompleted)
        defaults.set(true, forKey: SettingsKeys.starterContentSeeded)
        let info = Bundle.main.infoDictionary
        let version = "v\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
        defaults.set(WhatsNew.versionToRemember(currentVersion: version), forKey: SettingsKeys.seenVersion)
    }

    /// A believable week of use, so the dashboard isn't a row of zeros.
    private static func stats() -> Data? {
        var stats = UsageStats()
        let perDay: [(UsageMetric, Int)] = [(.errorsFixed, 9), (.dictatedWords, 640),
                                           (.layoutSwitches, 23), (.snippetsInserted, 6)]
        for day in 0..<7 {
            let date = Date().addingTimeInterval(-Double(day) * 86_400)
            for (metric, base) in perDay {
                stats.add(metric, count: base + (day * 7) % 5, on: date)
            }
        }
        return try? JSONEncoder().encode(stats)
    }
}
#endif
