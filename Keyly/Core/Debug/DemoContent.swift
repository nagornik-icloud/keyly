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
    ///
    /// One exception, explicit and Debug-only: `KEYLY_VITRINA_GEMINI_KEY` puts a real Gemini key
    /// behind the demo "Work" entry, so the showcase typo frame can show the product's REAL answer
    /// to a demo sentence (`VitrinaFieldShots`). The value lives only in this process's memory —
    /// nothing writes it to the keychain or defaults, and no frame shows a key.
    static var apiKeys: [APIKeyEntry] {
        let gemini = ProcessInfo.processInfo.environment["KEYLY_VITRINA_GEMINI_KEY"] ?? ""
        return [
            APIKeyEntry(id: openAIKeyID, name: "Personal", value: "demo-key-openai-0000",
                        provider: .openai, isBuiltin: false, model: nil),
            APIKeyEntry(id: geminiKeyID, name: "Work",
                        value: gemini.isEmpty ? "demo-key-gemini-0000" : gemini,
                        provider: .gemini, isBuiltin: false, model: nil),
        ]
    }

    /// True when a real key was handed in for the showcase typo frame (see `apiKeys`).
    static var hasVitrinaGeminiKey: Bool {
        !(ProcessInfo.processInfo.environment["KEYLY_VITRINA_GEMINI_KEY"] ?? "").isEmpty
    }

    /// Typo fixing through the demo "Work" (Gemini) entry — for the showcase frame only.
    static var geminiErrorFixSelection: APIKeySelection {
        APIKeySelection(provider: .gemini, keyId: geminiKeyID, model: APIProvider.gemini.defaultModel)
    }

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

        // Russian frames get Russian demo names: a Russian UI listing "Translate to English" and
        // "Make it polite" reads as an unfinished translation, not as the product.
        let ru = isRussian
        _ = CustomModuleStore.save([
            CustomAIModule(name: ru ? "Перевод на английский" : "Translate to English",
                           prompt: ru ? "Переведи текст на естественный, живой английский. Сохрани форматирование."
                                      : "Translate the text into natural, fluent English. Keep the formatting.",
                           hotKey: combo(kVK_ANSI_E, [.control, .option]),
                           textSource: .selected, output: .insert),
            CustomAIModule(name: ru ? "Сделать вежливо" : "Make it polite",
                           prompt: ru ? "Перепиши сообщение так, чтобы оно звучало дружелюбно и профессионально."
                                      : "Rewrite the message so it sounds friendly and professional.",
                           hotKey: combo(kVK_ANSI_P, [.control, .option]),
                           textSource: .selected, output: .insert),
            CustomAIModule(name: ru ? "Выжимка" : "Summarize",
                           prompt: ru ? "Сократи текст до трёх коротких пунктов."
                                      : "Summarize the text in three short bullet points.",
                           hotKey: combo(kVK_ANSI_M, [.control, .option]),
                           textSource: .selected, output: .panel),
        ])

        _ = SnippetStore.save([
            Snippet(name: ru ? "Почта" : "Email", content: "hello@example.com", triggers: ["@@mail"]),
            Snippet(name: ru ? "Приветствие" : "Greeting",
                    content: ru ? "Здравствуйте! Спасибо, что написали, — отвечу сегодня."
                                : "Hi! Thanks for reaching out — I'll get back to you today.",
                    triggers: ["@@hi"]),
            Snippet(name: ru ? "Адрес" : "Address",
                    content: ru ? "Невский проспект, 28, Санкт-Петербург" : "221B Baker Street, London",
                    hotKey: combo(kVK_ANSI_A, [.control, .option, .command])),
            Snippet(name: ru ? "Подпись" : "Signature",
                    content: ru ? "С уважением,\nАлексей" : "Best regards,\nAlex", triggers: [";sig"],
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

        // Showcase frame for "one bare key, even a Mac system key" (15.11.2026): the F-row keys
        // macOS doesn't let you remap, with no modifiers — F3 (Mission Control) → typo fix,
        // F4 (Spotlight) → Claude, F5 (dictation) → voice. These are the owner's real habits.
        // Codes are the built-in keyboard's media variants; `KeyCombo` names them F3/F4/F5.
        if ProcessInfo.processInfo.environment["KEYLY_DEMO_FKEYS"] == "1" {
            defaults.set(try? JSONEncoder().encode(combo(160, [])), forKey: SettingsKeys.errorFixHotKey)
            defaults.set(try? JSONEncoder().encode(combo(176, [])), forKey: SettingsKeys.voiceHotKey)
            AppLauncherStore.shared.replace(all: [
                AppLaunchShortcut(appPath: "/Applications/Claude.app", keyCombo: combo(177, [])),
                AppLaunchShortcut(appPath: "/Applications/Safari.app",
                                  keyCombo: combo(kVK_ANSI_S, [.control, .option])),
                AppLaunchShortcut(appPath: "/System/Applications/Notes.app",
                                  keyCombo: combo(kVK_ANSI_N, [.control, .option])),
            ])
        }

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

    /// The demo set follows the capture language (`KEYLY_QA_LANG=ru`), not the system one:
    /// frames for the Russian page must not depend on the machine they were shot on.
    nonisolated static var isRussian: Bool {
        ProcessInfo.processInfo.environment["KEYLY_QA_LANG"] == "ru"
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
