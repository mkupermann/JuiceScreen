import Testing
@testable import JuiceScreen

@Suite("FakePermissionsService")
struct FakePermissionsServiceTests {

    @Test("Returns configured status")
    func returnsConfiguredStatus() {
        let fake = FakePermissionsService(initial: [
            .screenRecording: .granted,
            .microphone: .denied,
            .inputMonitoring: .notDetermined
        ])
        #expect(fake.status(for: .screenRecording) == .granted)
        #expect(fake.status(for: .microphone) == .denied)
        #expect(fake.status(for: .inputMonitoring) == .notDetermined)
    }

    @Test("Defaults to notDetermined")
    func defaultsToNotDetermined() {
        let fake = FakePermissionsService()
        #expect(fake.status(for: .screenRecording) == .notDetermined)
    }

    @Test("Request transitions notDetermined to the configured next status")
    func requestUsesNextStatus() async {
        let fake = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        fake.nextStatusOnRequest[.screenRecording] = .granted
        let result = await fake.request(.screenRecording)
        #expect(result == .granted)
        #expect(fake.status(for: .screenRecording) == .granted)
    }

    @Test("Request is no-op if already determined")
    func requestNoOpIfDetermined() async {
        let fake = FakePermissionsService(initial: [.screenRecording: .granted])
        fake.nextStatusOnRequest[.screenRecording] = .denied
        let result = await fake.request(.screenRecording)
        #expect(result == .granted)
    }

    @Test("openSettings records the call for tests to inspect")
    func openSettingsRecorded() {
        let fake = FakePermissionsService()
        fake.openSettings(for: .microphone)
        fake.openSettings(for: .screenRecording)
        #expect(fake.openedSettingsFor == [.microphone, .screenRecording])
    }
}
