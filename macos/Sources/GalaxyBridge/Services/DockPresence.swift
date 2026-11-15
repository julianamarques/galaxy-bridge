import AppKit

@MainActor
final class DockPresence {
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let closing = name == NSWindow.willCloseNotification ? notification.object as? NSWindow : nil
                MainActor.assumeIsolated { self?.update(ignoring: closing) }
            }
        }
    }

    private func update(ignoring closing: NSWindow?) {
        DispatchQueue.main.async {
            let visible = NSApp.windows.contains { window in
                window !== closing && (window.isVisible || window.isMiniaturized) && Self.isDocumentWindow(window)
            }
            let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
            guard NSApp.activationPolicy() != policy else { return }
            NSApp.setActivationPolicy(policy)
            if visible { NSApp.activate() }
        }
    }

    private static func isDocumentWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel)
    }
}
