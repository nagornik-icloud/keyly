import Foundation

/// Starter content for the first launch.
///
/// An empty app doesn't explain itself: the user sees "No snippets yet" and understands
/// neither what to put there nor how it looks in use. Two ready examples answer both questions
/// in a second and can be deleted in one move.
///
/// Created ONCE per install — via a separate flag, not "if the list is empty": otherwise a
/// user who deleted the examples would get them back on every launch.
enum StarterContent {

    static func seedIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: SettingsKeys.starterContentSeeded) else { return }
        defaults.set(true, forKey: SettingsKeys.starterContentSeeded)

        // Seed only into an EMPTY list: if the user already has their own items (e.g. after
        // upgrading from an older version), examples aren't needed and would get in the way.
        if SnippetStore.load().isEmpty {
            _ = SnippetStore.save(exampleSnippets())
            Log.info(.snippets, "Стартовый контент: добавлены примеры сниппетов")
        }
        if CustomModuleStore.load().isEmpty {
            _ = CustomModuleStore.save([exampleModule()])
            Log.info(.modules, "Стартовый контент: добавлен пример модуля")
        }
    }

    /// Examples deliberately have NO hotkeys: we must not take shortcuts on the user's behalf,
    /// and they'll see the trigger in the list and try it right away.
    static func exampleSnippets() -> [Snippet] {
        [
            Snippet(name: "starter.snippet.email.name".loc,
                    content: "starter.snippet.email.content".loc,
                    triggers: ["@@mail"],
                    triggerMode: .afterSeparator),
            Snippet(name: "starter.snippet.today.name".loc,
                    content: "starter.snippet.today.content".loc,
                    // A Latin trigger: a Cyrillic example can't be typed without switching
                    // layouts — exactly what the app is meant to spare you.
                    triggers: ["@@hi"],
                    triggerMode: .afterSeparator),
        ]
    }

    static func exampleModule() -> CustomAIModule {
        CustomAIModule(name: "starter.module.name".loc,
                       prompt: "starter.module.prompt".loc,
                       textSource: .selected,
                       output: .copy)
    }
}
