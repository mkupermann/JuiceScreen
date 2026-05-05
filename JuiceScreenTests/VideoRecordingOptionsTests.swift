import Foundation
import Testing
@testable import JuiceScreen

@Suite("VideoRecordingOptions")
struct VideoRecordingOptionsTests {

    @Test("Defaults match spec: 60fps + system audio on + cursor ring on + click pulse off + keystrokes off")
    func defaults() {
        let o = VideoRecordingOptions.defaults
        #expect(o.targetFps == 60)
        #expect(o.captureSystemAudio == true)
        #expect(o.captureMicrophone == false)
        #expect(o.showCursorHighlight == true)
        #expect(o.showClickPulse == false)
        #expect(o.showKeystrokes == false)
    }

    @Test("Equatable")
    func equatable() {
        var a = VideoRecordingOptions.defaults
        var b = VideoRecordingOptions.defaults
        #expect(a == b)
        a.captureMicrophone = true
        #expect(a != b)
        b.captureMicrophone = true
        #expect(a == b)
    }

    @Test("requiresInputMonitoring is true iff click pulse OR keystrokes are enabled")
    func requiresInputMonitoring() {
        var o = VideoRecordingOptions.defaults
        #expect(o.requiresInputMonitoring == false)
        o.showClickPulse = true
        #expect(o.requiresInputMonitoring == true)
        o.showClickPulse = false
        o.showKeystrokes = true
        #expect(o.requiresInputMonitoring == true)
    }
}
