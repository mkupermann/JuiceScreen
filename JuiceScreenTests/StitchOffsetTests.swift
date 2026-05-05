import Testing
@testable import JuiceScreen

struct StitchOffsetTests {

    @Test("storage: constructor sets fields")
    func storage() {
        let offset = StitchOffset(pixelsScrolled: 42, ssdScore: 12345.6)
        #expect(offset.pixelsScrolled == 42)
        #expect(offset.ssdScore == 12345.6)
    }

    @Test("isUsable: good, zero, negative, high SSD")
    func isUsable() {
        #expect(StitchOffset(pixelsScrolled: 50, ssdScore: 100).isUsable == true)
        #expect(StitchOffset(pixelsScrolled: 0, ssdScore: 0).isUsable == false)
        #expect(StitchOffset(pixelsScrolled: -5, ssdScore: 10).isUsable == false)
        #expect(StitchOffset(pixelsScrolled: 50, ssdScore: 1_000_000).isUsable == false)
    }

    @Test("equatable")
    func equatable() {
        let a = StitchOffset(pixelsScrolled: 10, ssdScore: 200)
        let b = StitchOffset(pixelsScrolled: 10, ssdScore: 200)
        let c = StitchOffset(pixelsScrolled: 99, ssdScore: 200)
        #expect(a == b)
        #expect(a != c)
    }
}
