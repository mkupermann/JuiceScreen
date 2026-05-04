import Foundation
import Testing
@testable import JuiceScreen

@Suite("FirstRunCoordinator")
@MainActor
struct FirstRunCoordinatorTests {

    private func ephemeralStore() -> PreferencesStore {
        let suite = "JuiceScreenTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PreferencesStore(defaults: defaults)
    }

    @Test("Initial state is awaitingScreenRecording when permission notDetermined")
    func initialNotDetermined() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        #expect(coordinator.state == .awaitingScreenRecording)
    }

    @Test("If screen recording already granted on first run, jumps to hotkey wizard")
    func grantedJumpsToHotkeys() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        #expect(coordinator.state == .awaitingHotkeyDecision)
    }

    @Test("If first run already complete, state is .done immediately")
    func alreadyComplete() {
        let store = ephemeralStore()
        var prefs = store.load()
        prefs.firstRunComplete = true
        store.save(prefs)
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        #expect(coordinator.state == .done)
    }

    @Test("Granting permission advances to hotkey decision")
    func grantAdvances() async {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .notDetermined])
        perms.nextStatusOnRequest[.screenRecording] = .granted
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        await coordinator.requestScreenRecording()
        #expect(coordinator.state == .awaitingHotkeyDecision)
    }

    @Test("Hotkey decision advances to welcome")
    func hotkeyDecisionAdvances() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        coordinator.acceptHotkeyDefaults()
        #expect(coordinator.state == .awaitingWelcomeDismiss)
    }

    @Test("Dismissing welcome marks first run complete and reaches .done")
    func welcomeDismissPersists() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        coordinator.acceptHotkeyDefaults()
        coordinator.dismissWelcome()
        #expect(coordinator.state == .done)
        #expect(store.load().firstRunComplete == true)
    }

    @Test("Choosing alternative hotkeys writes them to preferences")
    func alternativeHotkeysPersist() {
        let store = ephemeralStore()
        let perms = FakePermissionsService(initial: [.screenRecording: .granted])
        let coordinator = FirstRunCoordinator(permissions: perms, preferences: store)
        coordinator.start()
        coordinator.useAlternativeHotkeys()
        let prefs = store.load()
        // Alternatives use ⌘⌃ instead of ⌘⇧ to avoid the macOS screenshot conflict
        #expect(prefs.captureRegionHotkey.modifiers == [.command, .control])
        #expect(prefs.captureFullScreenHotkey.modifiers == [.command, .control])
        #expect(prefs.recordScreenHotkey.modifiers == [.command, .control])
    }
}
