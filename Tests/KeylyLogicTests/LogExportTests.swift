import Foundation
import Testing
@testable import KeylyLogic

/// Log export for a bug report.
struct LogExportTests {

    @Test("Имя файла несёт дату и время — иначе второй багрепорт затрёт первый")
    func fileNameCarriesTimestamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26,
                                                     hour: 9, minute: 5))!
        #expect(LogExport.suggestedFileName(now: date, calendar: calendar)
                == "keyly-log-20260726-0905.txt")
    }

    @Test("Имена для разных минут различаются")
    func differentMinutesDifferentNames() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2,
                                                       hour: 3, minute: 4))!
        let second = first.addingTimeInterval(60)
        #expect(LogExport.suggestedFileName(now: first, calendar: calendar)
                != LogExport.suggestedFileName(now: second, calendar: calendar))
    }

    @Test("Окно выгрузки задано и не пустое")
    func windowIsSet() {
        #expect(!LogExport.window.isEmpty)
    }
}
