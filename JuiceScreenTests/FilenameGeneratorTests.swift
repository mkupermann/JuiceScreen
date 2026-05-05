import Foundation
import Testing
@testable import JuiceScreen

@Suite("FilenameGenerator")
struct FilenameGeneratorTests {

    private let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test("Default PNG filename for a known timestamp")
    func pngFilename() {
        let comps = DateComponents(year: 2026, month: 5, day: 4, hour: 14, minute: 32, second: 18)
        let date = utcCalendar.date(from: comps)!
        let gen = FilenameGenerator(calendar: utcCalendar)
        #expect(gen.filename(for: date, extension: "png") ==
                "JuiceScreen_2026-05-04_at_14.32.18.png")
    }

    @Test("Different extensions are honored")
    func differentExtensions() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        let gen = FilenameGenerator(calendar: utcCalendar)
        #expect(gen.filename(for: date, extension: "jpg") == "JuiceScreen_2026-01-02_at_03.04.05.jpg")
        #expect(gen.filename(for: date, extension: "mp4") == "JuiceScreen_2026-01-02_at_03.04.05.mp4")
    }

    @Test("Zero-padding for single-digit month / day / time components")
    func zeroPadding() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        let gen = FilenameGenerator(calendar: utcCalendar)
        let name = gen.filename(for: date, extension: "png")
        #expect(name == "JuiceScreen_2026-01-02_at_03.04.05.png")
    }

    @Test("Date subfolder ('2026-05-04') for grouping")
    func subfolderName() {
        let date = utcCalendar.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        let gen = FilenameGenerator(calendar: utcCalendar)
        #expect(gen.dateSubfolderName(for: date) == "2026-05-04")
    }
}
