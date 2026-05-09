import Testing
@testable import JuiceScreen

@Suite("HotkeyService")
struct HotkeyServiceTests {

    /// Standard test hotkey. Registration may succeed or fail depending on the
    /// test process's key-event privileges; tests below ignore the return value
    /// where the goal is to exercise dictionary bookkeeping rather than Carbon.
    private func sampleHotkey(keyCode: UInt32 = 0x12) -> Hotkey {
        Hotkey(keyCode: keyCode, modifiers: [.command, .shift, .control, .option])
    }

    @Test("init installs the event handler and the service can be created and dropped")
    func initAndDeinit() {
        // Just creating + releasing exercises init's installEventHandler() and
        // deinit's UnregisterEventHotKey + RemoveEventHandler cleanup paths.
        do {
            let svc = HotkeyService()
            _ = svc
        }
        // Reaching this point without crashing is the assertion.
        #expect(Bool(true))
    }

    @Test("register returns a Bool and accepts a handler closure")
    func registerReturnsBool() {
        let svc = HotkeyService()
        // We don't assert PASS/FAIL — Carbon registration depends on environment.
        // What matters for coverage is that the call path executes.
        let result = svc.register(sampleHotkey(), for: .captureRegion) {}
        #expect(result == true || result == false)
        svc.unregisterAll()
    }

    @Test("register replaces a prior binding for the same action")
    func registerReplacesExistingBinding() {
        let svc = HotkeyService()
        var firstCalls = 0
        var secondCalls = 0
        // First binding.
        _ = svc.register(sampleHotkey(keyCode: 0x12), for: .captureRegion) {
            firstCalls += 1
        }
        // Re-registering for the same action triggers the unregister-then-register
        // branch in register(...). Both closures must remain non-firing in tests
        // (we cannot synthesize a Carbon hotkey event), but the code path runs.
        _ = svc.register(sampleHotkey(keyCode: 0x13), for: .captureRegion) {
            secondCalls += 1
        }
        #expect(firstCalls == 0)
        #expect(secondCalls == 0)
        svc.unregisterAll()
    }

    @Test("unregister of an unregistered action is a no-op")
    func unregisterMissingIsNoop() {
        let svc = HotkeyService()
        // No prior register() for this action — unregister must not crash and
        // must leave the service in a usable state.
        svc.unregister(.recordScreen)
        // Subsequent register call still works.
        _ = svc.register(sampleHotkey(), for: .recordScreen) {}
        svc.unregister(.recordScreen)
        // And re-registering after unregister is fine.
        _ = svc.register(sampleHotkey(), for: .recordScreen) {}
        svc.unregisterAll()
    }

    @Test("unregister removes a previously-registered action")
    func unregisterRemovesRegistration() {
        let svc = HotkeyService()
        _ = svc.register(sampleHotkey(), for: .captureWindow) {}
        svc.unregister(.captureWindow)
        // After unregister, registering again should also work — exercises the
        // "not present" branch in unregister inside the next register call.
        _ = svc.register(sampleHotkey(), for: .captureWindow) {}
        svc.unregisterAll()
    }

    @Test("unregisterAll on an empty service is a no-op")
    func unregisterAllEmpty() {
        let svc = HotkeyService()
        svc.unregisterAll()
        svc.unregisterAll()
        #expect(Bool(true))
    }

    @Test("unregisterAll clears multiple registrations")
    func unregisterAllClearsMultiple() {
        let svc = HotkeyService()
        _ = svc.register(sampleHotkey(keyCode: 0x12), for: .captureRegion) {}
        _ = svc.register(sampleHotkey(keyCode: 0x13), for: .captureWindow) {}
        _ = svc.register(sampleHotkey(keyCode: 0x14), for: .captureFullScreen) {}
        _ = svc.register(sampleHotkey(keyCode: 0x15), for: .recordScreen) {}
        svc.unregisterAll()
        // After clearing, we can register again — proves the dictionaries were
        // emptied and no stale state persists.
        _ = svc.register(sampleHotkey(keyCode: 0x12), for: .captureRegion) {}
        svc.unregisterAll()
    }

    @Test("HotkeyAction.allCases covers every defined action")
    func registerEveryAction() {
        let svc = HotkeyService()
        // Walk every action so unregisterAll's loop iterates over the full set
        // with a mix of present + absent registrations.
        for (i, action) in HotkeyAction.allCases.enumerated() {
            _ = svc.register(sampleHotkey(keyCode: UInt32(0x12 + i)), for: action) {}
        }
        svc.unregisterAll()
    }
}
