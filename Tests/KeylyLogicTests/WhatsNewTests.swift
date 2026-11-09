import Testing
@testable import KeylyLogic

/// The "What's new" card.
///
/// Errors are silent both ways: not showing it means the user never learns about new features;
/// showing it again means the card returns after every launch and looks like an ad.
struct WhatsNewTests {

    @Test("Версия сменилась — показываем")
    func newVersionShows() {
        #expect(WhatsNew.shouldShow(currentVersion: "2.1", seenVersion: "2.0"))
    }

    @Test("Та же версия — не показываем")
    func sameVersionHidden() {
        #expect(!WhatsNew.shouldShow(currentVersion: "2.1", seenVersion: "2.1"))
    }

    @Test("Первый запуск — не показываем: человека встречает визард")
    func firstLaunchHidden() {
        #expect(!WhatsNew.shouldShow(currentVersion: "2.1", seenVersion: nil))
        #expect(!WhatsNew.shouldShow(currentVersion: "2.1", seenVersion: ""))
    }

    @Test("Пустая текущая версия ничего не показывает — это сбой сборки, а не событие")
    func emptyCurrentHidden() {
        #expect(!WhatsNew.shouldShow(currentVersion: "", seenVersion: "2.0"))
    }

    @Test("Откат версии тоже считается сменой — показываем")
    func downgradeShows() {
        // The user may have gone back to an old build; it helps them to see what exactly is there.
        #expect(WhatsNew.shouldShow(currentVersion: "2.0", seenVersion: "2.1"))
    }

    @Test("После закрытия запоминается ТЕКУЩАЯ версия, а не флаг")
    func remembersVersionNotFlag() {
        // A boolean flag would have to be reset by hand on every release; one day someone would forget.
        #expect(WhatsNew.versionToRemember(currentVersion: "3.0") == "3.0")
        #expect(!WhatsNew.shouldShow(currentVersion: "3.0",
                                     seenVersion: WhatsNew.versionToRemember(currentVersion: "3.0")))
    }
}
