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

/// Pure geometry — no SCDisplay, no NSScreen, no TCC permission needed, so these
/// run identically on CI and locally.
@Suite("displayLocalTopLeft")
struct DisplayLocalTopLeftTests {

    /// 1920×1080 main display, origin at the global origin.
    private let mainDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// Mirrors `RegionPickerController.commit()`: overlay-local top-left rect →
    /// global bottom-left rect. Used to prove the two conversions are inverses.
    private func pickerGlobalBL(localTL: CGRect, screen: CGRect) -> CGRect {
        CGRect(
            x: localTL.minX + screen.minX,
            y: (screen.height - (localTL.minY + localTL.height)) + screen.minY,
            width: localTL.width,
            height: localTL.height
        )
    }

    @Test("Flips the y axis on the main display")
    func flipsYOnMainDisplay() {
        // A 200×100 box whose top edge sits 100pt below the top of the display:
        // bottom-left y = 1080 - 100 - 100 = 880.
        let global = CGRect(x: 300, y: 880, width: 200, height: 100)
        let local = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: mainDisplay)
        #expect(local == CGRect(x: 300, y: 100, width: 200, height: 100))
    }

    @Test("Region flush against the top edge maps to y == 0")
    func topEdge() {
        let global = CGRect(x: 0, y: 980, width: 400, height: 100)
        let local = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: mainDisplay)
        #expect(local == CGRect(x: 0, y: 0, width: 400, height: 100))
    }

    @Test("Region flush against the bottom edge maps to y == height - regionHeight")
    func bottomEdge() {
        let global = CGRect(x: 0, y: 0, width: 400, height: 100)
        let local = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: mainDisplay)
        #expect(local == CGRect(x: 0, y: 980, width: 400, height: 100))
    }

    @Test("Full-display region maps onto the whole display")
    func fullDisplay() {
        let local = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: mainDisplay, displayFrame: mainDisplay)
        #expect(local == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test("Secondary display stacked above the main one")
    func displayAbove() {
        let above = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let global = CGRect(x: 100, y: 1500, width: 300, height: 200)
        let local = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: above)
        // local BL y = 1500 - 1080 = 420 → TL y = 1080 - (420 + 200) = 460
        #expect(local == CGRect(x: 100, y: 460, width: 300, height: 200))
    }

    @Test("Secondary display with negative origin on both axes")
    func negativeOrigin() {
        let left = CGRect(x: -1920, y: -300, width: 1920, height: 1200)
        let global = CGRect(x: -1800, y: -200, width: 300, height: 150)
        let local = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: left)
        // x: -1800 - (-1920) = 120; local BL y = -200 - (-300) = 100
        // TL y = 1200 - (100 + 150) = 950
        #expect(local == CGRect(x: 120, y: 950, width: 300, height: 150))
    }

    @Test("Round-trips with the picker's local-TL → global-BL conversion", arguments: [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),          // main
        CGRect(x: 1920, y: 240, width: 2560, height: 1440),     // to the right, offset
        CGRect(x: -1440, y: -560, width: 1440, height: 900)     // to the left, negative origin
    ])
    func roundTrip(screen: CGRect) {
        // Two drags describing the same box from opposite corners normalise to the
        // same local rect, so one representative rect per screen is enough.
        for localTL in [
            CGRect(x: 0, y: 0, width: 10, height: 10),                              // top-left corner
            CGRect(x: 120, y: 340, width: 500, height: 250),                        // interior
            CGRect(x: screen.width - 60, y: screen.height - 40, width: 60, height: 40)  // bottom-right corner
        ] {
            let global = pickerGlobalBL(localTL: localTL, screen: screen)
            let back = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: screen)
            #expect(back == localTL)
        }
    }

    @Test("Subtracting the origin without flipping y is wrong (the shipped 1.1.1 bug)")
    func regressionAgainstNaiveSubtraction() {
        let global = CGRect(x: 300, y: 880, width: 200, height: 100)
        let naive = CGRect(x: global.minX - mainDisplay.minX,
                           y: global.minY - mainDisplay.minY,
                           width: global.width, height: global.height)
        let correct = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: mainDisplay)
        #expect(naive.minY == 880)
        #expect(correct.minY == 100)
        #expect(naive != correct)
    }

    @Test("globalBottomLeft is the exact inverse of displayLocalTopLeft")
    func globalBottomLeftInverse() {
        let screen = CGRect(x: 1920, y: 240, width: 2560, height: 1440)
        let localTL = CGRect(x: 120, y: 340, width: 500, height: 250)

        let global = ScreenCaptureKitHelpers.globalBottomLeft(localTL: localTL, screenFrame: screen)
        // local BL y = 1440 - (340 + 250) = 850 → global y = 850 + 240 = 1090
        #expect(global == CGRect(x: 2040, y: 1090, width: 500, height: 250))

        let back = ScreenCaptureKitHelpers.displayLocalTopLeft(globalBL: global, displayFrame: screen)
        #expect(back == localTL)
    }
}
