import AppKit
import Carbon.HIToolbox

/// Identifies a hotkey within JuiceScreen. Sent into Carbon as the EventHotKeyID `id`.
public enum HotkeyAction: UInt32, CaseIterable, Sendable {
    case captureRegion     = 1
    case captureWindow     = 2
    case captureFullScreen = 3
    case captureLastRegion = 4
    case recordScreen      = 5
    case openLibrary       = 6
    case stopRecording     = 7  // dynamically (un)bound during a recording session
    case captureScroll     = 8
}

/// Registers global hotkeys via Carbon and dispatches their fire events to a closure.
/// One service instance per process. Not thread-safe; call from the main thread.
public final class HotkeyService {

    private let log = AppLog.logger(category: "HotkeyService")
    private let signature: OSType = OSType(0x4A555352) // 'JUSR'

    private var registrations: [HotkeyAction: EventHotKeyRef] = [:]
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    public init() {
        installEventHandler()
    }

    deinit {
        for (_, ref) in registrations {
            UnregisterEventHotKey(ref)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Registers `hotkey` for `action`. Replaces any prior binding for the same action.
    /// Returns true if registration succeeded.
    @discardableResult
    public func register(_ hotkey: Hotkey, for action: HotkeyAction, handler: @escaping () -> Void) -> Bool {
        unregister(action)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifierMask,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for \(action.rawValue): OSStatus=\(status)")
            return false
        }
        registrations[action] = ref
        handlers[action] = handler
        return true
    }

    public func unregister(_ action: HotkeyAction) {
        if let ref = registrations.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: action)
    }

    public func unregisterAll() {
        for action in HotkeyAction.allCases {
            unregister(action)
        }
    }

    // MARK: - Carbon event handler bridge

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout.size(ofValue: hkID),
                    nil,
                    &hkID
                )
                guard status == noErr,
                      let action = HotkeyAction(rawValue: hkID.id) else { return noErr }
                service.handlers[action]?()
                return noErr
            },
            1,
            &spec,
            userData,
            &eventHandler
        )
    }
}
