import Testing
import Foundation
@testable import KeylyLogic

/// A launcher target is an app, folder, file OR link.
@Suite struct LaunchTargetTests {

    @Test func приложениеУзнаётсяПоРасширению() {
        let target = LaunchTarget.resolve("/Applications/Safari.app")
        #expect(target == .application(bundleId: nil, url: URL(fileURLWithPath: "/Applications/Safari.app")))
    }

    @Test func ссылкаУзнаётсяПоСхеме() {
        guard case .link(let url)? = LaunchTarget.resolve("https://example.com/page") else {
            Issue.record("ссылка не распознана"); return
        }
        #expect(url.absoluteString == "https://example.com/page")
    }

    @Test func папкаИФайлИдутОдинаково() {
        guard case .file? = LaunchTarget.resolve("/Users/me/Documents") else {
            Issue.record("папка не распознана"); return
        }
        guard case .file? = LaunchTarget.resolve("/Users/me/notes.txt") else {
            Issue.record("файл не распознан"); return
        }
    }

    /// Paths with spaces are common on macOS ("/Applications/Google Chrome.app").
    /// `URL(string:)` rejects such a string, and without a separate branch a file path
    /// would end up as a "link" or not be recognized at all.
    @Test func путьСПробеламиОстаётсяПутём() {
        guard case .application? = LaunchTarget.resolve("/Applications/Google Chrome.app") else {
            Issue.record("путь с пробелом не распознан как приложение"); return
        }
    }

    @Test func пустаяСтрокаНеЦель() {
        #expect(LaunchTarget.resolve("") == nil)
        #expect(LaunchTarget.resolve("   ") == nil)
    }

    /// A link's display name is its host: a full URL crowds everything else out of the list row.
    @Test func имяСсылкиХост() {
        #expect(LaunchTarget.suggestedName(for: "https://music.youtube.com/playlist?list=x") == "music.youtube.com")
        #expect(LaunchTarget.suggestedName(for: "/Applications/Safari.app") == "Safari")
    }
}

/// A target lives by bookmark, not by a path string.
@Suite struct LaunchShortcutBookmarkTests {

    /// Entries from the previous version have no bookmark, and that is not an error: the path stays a working
    /// fallback, otherwise an update would wipe all configured shortcuts.
    @Test func безЗакладкиИспользуетсяПуть() {
        let shortcut = AppLaunchShortcut(appPath: "/Applications/Safari.app", keyCombo: nil)
        #expect(shortcut.bookmark == nil)
        #expect(shortcut.resolvedURL.path == "/Applications/Safari.app")
    }

    /// A broken bookmark must not break launching: return the saved path and give the target a chance.
    @Test func битаяЗакладкаПадаетНаПуть() {
        let shortcut = AppLaunchShortcut(appPath: "/Applications/Safari.app",
                                         keyCombo: nil,
                                         bookmark: Data([0x00, 0x01, 0x02]))
        #expect(shortcut.resolvedURL.path == "/Applications/Safari.app")
    }

    @Test func закладкаЗаводитсяДляСуществующегоПути() {
        let url = URL(fileURLWithPath: "/Applications")
        #expect(AppLaunchShortcut.makeBookmark(for: url) != nil)
    }

    /// Decoding an old entry without the `bookmark` field must succeed: otherwise the target list
    /// would be empty after an update.
    @Test func староеJSONБезЗакладкиДекодируется() throws {
        let json = """
        [{"id":"44444444-4444-4444-4444-444444444444","appPath":"/Applications/Safari.app","appName":"Safari"}]
        """.data(using: .utf8)!
        let list = try JSONDecoder().decode([AppLaunchShortcut].self, from: json)
        #expect(list.count == 1)
        #expect(list[0].bookmark == nil)
    }
}
