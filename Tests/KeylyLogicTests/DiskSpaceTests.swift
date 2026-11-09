import Testing
@testable import KeylyLogic

/// Disk space check before downloading a model.
struct DiskSpaceTests {

    private var required: Int64 { DiskSpace.modelBytes + DiskSpace.headroomBytes }

    @Test("Места хватает ровно впритык — пускаем")
    func exactlyEnoughPasses() {
        #expect(DiskSpace.check(availableBytes: required) == .enough)
    }

    @Test("На байт меньше — отказ с ОБОИМИ числами")
    func oneByteShortRefuses() {
        let verdict = DiskSpace.check(availableBytes: required - 1)
        #expect(verdict == .notEnough(requiredBytes: required, availableBytes: required - 1))
    }

    @Test("Запас сверх модели заложен — на голом размере модели не пускаем")
    func headroomIsRequired() {
        // Unpacking and compiling need space, and the system behaves unpredictably on a full disk
        // long before zero.
        #expect(DiskSpace.check(availableBytes: DiskSpace.modelBytes) != .enough)
    }

    @Test("Не смогли измерить — НЕ блокируем")
    func unknownDoesNotBlock() {
        // Refusing because we cannot measure is worse than letting the user try.
        #expect(DiskSpace.check(availableBytes: nil) == .unknown)
    }

    @Test("Объём форматируется человекочитаемо")
    func formatsHumanReadable() {
        let text = DiskSpace.format(DiskSpace.modelBytes)
        #expect(!text.isEmpty)
        #expect(text.rangeOfCharacter(from: .decimalDigits) != nil)
    }
}
