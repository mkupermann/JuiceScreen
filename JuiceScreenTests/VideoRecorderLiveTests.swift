import Foundation
import Testing
@testable import JuiceScreen

/// Covers the permission-validation prologue of `VideoRecorderLive.start()`.
/// The actual ScreenCaptureKit call (`SCShareableContent.excludingDesktopWindows`)
/// requires real screen access and is not exercised here — these tests stop
/// before we reach it by setting up the FakePermissionsService to deny first.
@Suite("VideoRecorderLive")
@MainActor
struct VideoRecorderLiveTests {

    private let outputURL = URL(fileURLWithPath: "/tmp/jc-vrl-out.mp4")

    @Test("init: isRecording=false, elapsed=0")
    func initialState() {
        let perms = FakePermissionsService()
        let recorder = VideoRecorderLive(permissions: perms)
        #expect(recorder.isRecording == false)
        #expect(recorder.elapsed == 0)
    }

    @Test("start throws missingScreenRecordingPermission when screen recording is denied")
    func deniedScreenRecording() async {
        let perms = FakePermissionsService(initial: [.screenRecording: .denied])
        let recorder = VideoRecorderLive(permissions: perms)
        do {
            try await recorder.start(mode: .fullScreen, options: .defaults, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            #expect(error == .missingScreenRecordingPermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(recorder.isRecording == false)
    }

    @Test("start throws missingScreenRecordingPermission when screen recording is notDetermined")
    func notDeterminedScreenRecording() async {
        // The guard checks `== .granted`, so .notDetermined also throws.
        let perms = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        let recorder = VideoRecorderLive(permissions: perms)
        do {
            try await recorder.start(mode: .fullScreen, options: .defaults, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            #expect(error == .missingScreenRecordingPermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("start throws missingMicrophonePermission when mic capture requested but denied")
    func deniedMicrophone() async {
        let perms = FakePermissionsService(initial: [
            .screenRecording: .granted,
            .microphone: .denied,   // request() returns .denied because not .notDetermined
        ])
        let recorder = VideoRecorderLive(permissions: perms)
        var opts = VideoRecordingOptions.defaults
        opts.captureMicrophone = true
        do {
            try await recorder.start(mode: .fullScreen, options: opts, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            #expect(error == .missingMicrophonePermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("start throws missingInputMonitoringPermission when click pulse requested but denied")
    func deniedInputMonitoringForClickPulse() async {
        let perms = FakePermissionsService(initial: [
            .screenRecording: .granted,
            .microphone: .granted,
            .inputMonitoring: .denied,
        ])
        let recorder = VideoRecorderLive(permissions: perms)
        var opts = VideoRecordingOptions.defaults
        opts.showClickPulse = true   // → requiresInputMonitoring == true
        do {
            try await recorder.start(mode: .fullScreen, options: opts, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            #expect(error == .missingInputMonitoringPermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("start throws missingInputMonitoringPermission when keystrokes requested but denied")
    func deniedInputMonitoringForKeystrokes() async {
        let perms = FakePermissionsService(initial: [
            .screenRecording: .granted,
            .inputMonitoring: .denied,
        ])
        let recorder = VideoRecorderLive(permissions: perms)
        var opts = VideoRecordingOptions.defaults
        opts.showKeystrokes = true   // → requiresInputMonitoring == true (other branch)
        do {
            try await recorder.start(mode: .fullScreen, options: opts, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            #expect(error == .missingInputMonitoringPermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("stop throws streamFailed when called without an active recording")
    func stopWithoutActiveRecording() async {
        let perms = FakePermissionsService()
        let recorder = VideoRecorderLive(permissions: perms)
        do {
            _ = try await recorder.stop()
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            if case .streamFailed = error {
                // Expected.
            } else {
                Issue.record("Unexpected VideoRecordingError case: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("elapsed stays at 0 before start; stays 0 after a failed start (state untouched on permission error)")
    func elapsedAfterFailedStart() async {
        let perms = FakePermissionsService(initial: [.screenRecording: .denied])
        let recorder = VideoRecorderLive(permissions: perms)
        try? await recorder.start(mode: .fullScreen, options: .defaults, outputURL: outputURL)
        #expect(recorder.elapsed == 0)
        #expect(recorder.isRecording == false)
    }

    @Test("region mode: permission denied throws before SCStream setup")
    func regionModeDeniedScreenRecording() async {
        let perms = FakePermissionsService(initial: [.screenRecording: .denied])
        let recorder = VideoRecorderLive(permissions: perms)
        let region = CGRect(x: 0, y: 0, width: 200, height: 100)
        do {
            try await recorder.start(mode: .region(region), options: .defaults, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            #expect(error == .missingScreenRecordingPermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("captureMicrophone + showClickPulse together: the FIRST denied permission wins (microphone)")
    func firstDeniedWinsMicrophone() async {
        let perms = FakePermissionsService(initial: [
            .screenRecording: .granted,
            .microphone: .denied,        // checked first
            .inputMonitoring: .denied,   // would also fail, but order matters
        ])
        let recorder = VideoRecorderLive(permissions: perms)
        var opts = VideoRecordingOptions.defaults
        opts.captureMicrophone = true
        opts.showClickPulse = true
        do {
            try await recorder.start(mode: .fullScreen, options: opts, outputURL: outputURL)
            Issue.record("Expected throw")
        } catch let error as VideoRecordingError {
            // Source checks microphone before input monitoring → microphone error wins.
            #expect(error == .missingMicrophonePermission)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("isRecording remains false across multiple failed starts")
    func multipleFailedStartsKeepStateFalse() async {
        let perms = FakePermissionsService(initial: [.screenRecording: .denied])
        let recorder = VideoRecorderLive(permissions: perms)
        for _ in 1 ... 3 {
            try? await recorder.start(mode: .fullScreen, options: .defaults, outputURL: outputURL)
        }
        #expect(recorder.isRecording == false)
    }
}
