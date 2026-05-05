import Foundation
import Testing
@testable import JuiceScreen

@Suite("FakeCaptureEngine")
struct FakeCaptureEngineTests {

    private func makeRecord(_ type: CaptureType) -> CaptureRecord {
        CaptureRecord(
            fileURL: URL(fileURLWithPath: "/tmp/fake.png"),
            captureType: type,
            capturedAt: Date(),
            pixelWidth: 100, pixelHeight: 100, sourceApp: nil
        )
    }

    @Test("Returns the configured record for each capture type")
    func returnsConfiguredRecord() async throws {
        let region = makeRecord(.region)
        let window = makeRecord(.window)
        let full = makeRecord(.fullScreen)
        let last = makeRecord(.lastRegion)

        let engine = FakeCaptureEngine()
        engine.recordsToReturn = [
            .region: .success(region),
            .window: .success(window),
            .fullScreen: .success(full),
            .lastRegion: .success(last),
        ]

        let r1 = try await engine.captureRegion()
        let r2 = try await engine.captureWindow()
        let r3 = try await engine.captureFullScreen()
        let r4 = try await engine.captureLastRegion()

        #expect(r1 == region)
        #expect(r2 == window)
        #expect(r3 == full)
        #expect(r4 == last)
    }

    @Test("Throws the configured error")
    func throwsConfiguredError() async {
        let engine = FakeCaptureEngine()
        engine.recordsToReturn[.region] = .failure(.userCancelled)

        await #expect(throws: CaptureError.self) {
            _ = try await engine.captureRegion()
        }
    }

    @Test("Records each call so tests can assert which capture types fired")
    func recordsCalls() async throws {
        let engine = FakeCaptureEngine()
        engine.recordsToReturn = [
            .region: .success(makeRecord(.region)),
            .window: .success(makeRecord(.window)),
        ]

        _ = try await engine.captureRegion()
        _ = try await engine.captureWindow()
        _ = try await engine.captureRegion()

        #expect(engine.calls == [.region, .window, .region])
    }

    @Test("Defaults to .userCancelled when no record is configured")
    func defaultBehavior() async {
        let engine = FakeCaptureEngine()
        await #expect(throws: CaptureError.self) {
            _ = try await engine.captureFullScreen()
        }
    }
}
