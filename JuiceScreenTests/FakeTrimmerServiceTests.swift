import CoreMedia
import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeTrimmerService")
struct FakeTrimmerServiceTests {

    private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    @Test("Returns the configured destination URL")
    func returnsConfigured() async throws {
        let svc = FakeTrimmerService()
        let dest = URL(fileURLWithPath: "/tmp/out.mp4")
        svc.nextResult = .success(dest)

        let result = try await svc.trim(
            sourceURL: URL(fileURLWithPath: "/tmp/in.mp4"),
            range: TrimRange(start: t(0), end: t(5)),
            destinationURL: dest
        )
        #expect(result == dest)
    }

    @Test("Throws the configured error")
    func throwsConfigured() async {
        let svc = FakeTrimmerService()
        svc.nextResult = .failure(.exportFailed("boom"))
        await #expect(throws: TrimmerError.self) {
            _ = try await svc.trim(
                sourceURL: URL(fileURLWithPath: "/tmp/in.mp4"),
                range: TrimRange(start: t(0), end: t(5)),
                destinationURL: URL(fileURLWithPath: "/tmp/out.mp4")
            )
        }
    }

    @Test("Records calls so tests can inspect inputs")
    func recordsCall() async throws {
        let svc = FakeTrimmerService()
        let source = URL(fileURLWithPath: "/tmp/in.mp4")
        let dest = URL(fileURLWithPath: "/tmp/out.mp4")
        let range = TrimRange(start: t(2), end: t(7))
        svc.nextResult = .success(dest)

        _ = try await svc.trim(sourceURL: source, range: range, destinationURL: dest)

        #expect(svc.calls.count == 1)
        #expect(svc.calls[0].sourceURL == source)
        #expect(svc.calls[0].destinationURL == dest)
        #expect(svc.calls[0].range == range)
    }
}
