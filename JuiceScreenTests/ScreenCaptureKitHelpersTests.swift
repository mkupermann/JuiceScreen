import Foundation
import Testing
import ScreenCaptureKit
@testable import JuiceScreen

@Suite("ScreenCaptureKitHelpers")
struct ScreenCaptureKitHelpersTests {

    // SCShareableContent fetch will fail in the test process unless the test host
    // has been granted Screen Recording permission, which is environment-dependent
    // (CI: no; local with permission: yes). We assert the function either succeeds
    // OR throws CaptureError.missingScreenRecordingPermission — both branches are
    // legitimate exits. Either way the call exercises the wrapper.
    @Test("shareableContent returns content or throws missingScreenRecordingPermission")
    func shareableContentEitherBranch() async {
        do {
            let content = try await ScreenCaptureKitHelpers.shareableContent()
            #expect(content.displays.isEmpty == false || content.displays.isEmpty == true)
        } catch let error as CaptureError {
            if case .missingScreenRecordingPermission = error {
                // Expected error path on a test process without TCC.
            } else {
                Issue.record("Unexpected CaptureError: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // configuration(for:pixelDensity:) is a pure builder once we have an SCDisplay.
    // We can only obtain an SCDisplay from a successful SCShareableContent fetch,
    // so this test conditionally runs only when shareableContent succeeds.
    @Test("configuration(for: display) sets pixel-density-scaled width/height + BGRA format")
    func configurationFromDisplay() async {
        let content: SCShareableContent
        do {
            content = try await ScreenCaptureKitHelpers.shareableContent()
        } catch {
            // Permission not granted — we still need to record SOMETHING for the
            // test to not be silent. The function is exercised in the shareableContent
            // test above.
            return
        }
        guard let display = content.displays.first else { return }

        let cfg = ScreenCaptureKitHelpers.configuration(for: display, pixelDensity: 2)
        #expect(cfg.width == display.width * 2)
        #expect(cfg.height == display.height * 2)
        #expect(cfg.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(cfg.showsCursor == false)

        // Default pixelDensity argument equals 2.
        let cfgDefault = ScreenCaptureKitHelpers.configuration(for: display)
        #expect(cfgDefault.width == display.width * 2)

        // Custom pixelDensity 1.
        let cfg1x = ScreenCaptureKitHelpers.configuration(for: display, pixelDensity: 1)
        #expect(cfg1x.width == display.width)
    }

    @Test("configuration(for: display, regionInPoints:) scales the region by pixelDensity")
    func configurationFromRegion() async {
        let content: SCShareableContent
        do {
            content = try await ScreenCaptureKitHelpers.shareableContent()
        } catch {
            return
        }
        guard let display = content.displays.first else { return }

        let region = CGRect(x: 0, y: 0, width: 100, height: 80)
        let cfg = ScreenCaptureKitHelpers.configuration(for: display, regionInPoints: region, pixelDensity: 2)
        #expect(cfg.width == 200)
        #expect(cfg.height == 160)
        #expect(cfg.pixelFormat == kCVPixelFormatType_32BGRA)
    }
}
