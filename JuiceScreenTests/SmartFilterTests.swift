import Foundation
import Testing
@testable import JuiceScreen

@Suite("SmartFilter")
struct SmartFilterTests {

    @Test("All cases enumerated")
    func allCases() {
        let expected: Set<SmartFilter> = [.all, .today, .thisWeek, .thisMonth, .videos, .images, .trash]
        #expect(Set(SmartFilter.allCases) == expected)
    }

    @Test("Display name + SF Symbol per case")
    func metadata() {
        #expect(SmartFilter.all.displayName == "All")
        #expect(SmartFilter.today.displayName == "Today")
        #expect(SmartFilter.thisWeek.displayName == "This Week")
        #expect(SmartFilter.thisMonth.displayName == "This Month")
        #expect(SmartFilter.videos.displayName == "Videos")
        #expect(SmartFilter.images.displayName == "Images")
        #expect(SmartFilter.trash.displayName == "Trash")

        #expect(SmartFilter.all.sfSymbol == "tray.full")
        #expect(SmartFilter.today.sfSymbol == "calendar")
        #expect(SmartFilter.trash.sfSymbol == "trash")
    }

    @Test("includesTrash is true only for .trash filter")
    func includesTrash() {
        for f in SmartFilter.allCases where f != .trash {
            #expect(f.includesTrash == false)
        }
        #expect(SmartFilter.trash.includesTrash == true)
    }
}
