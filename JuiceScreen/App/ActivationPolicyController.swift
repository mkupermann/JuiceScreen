import AppKit

/// Promotes the app from `.accessory` (no Dock icon) to `.regular` while any non-status
/// window is visible, then demotes back to `.accessory` once the last one closes.
/// Pattern used by Things, Bear, and other menu-bar-with-windows apps.
@MainActor
public final class ActivationPolicyController {

    private let log = AppLog.logger(category: "ActivationPolicy")
    private var observers: [NSObjectProtocol] = []

    public init() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.evaluate()
        })
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            // Re-evaluate after the window is removed from NSApp.windows.
            DispatchQueue.main.async { self?.evaluate() }
        })
        evaluate()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver(_:))
    }

    private func evaluate() {
        let hasUserWindow = NSApp.windows.contains { window in
            window.isVisible && !window.className.contains("StatusBar")
        }
        let desired: NSApplication.ActivationPolicy = hasUserWindow ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
            log.info("Activation policy → \(String(describing: desired))")
        }
    }
}
