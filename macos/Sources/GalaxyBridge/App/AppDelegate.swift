import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    private var callPanel: CallPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.launched()
        callPanel = CallPanel(app: app)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [app] _ in
            MainActor.assumeIsolated { app.systemDidWake() }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_MENU"] != nil { showMenuPreview() }
        if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_CALL"] != nil { app.previewIncomingCall() }
        #endif
    }

    #if DEBUG
    private var previewWindow: NSWindow?

    private func showMenuPreview() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.title = "Menu"
        window.contentView = NSHostingView(rootView: MenuView().environmentObject(app).environment(\.controlActiveState, .key))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        previewWindow = window
    }
    #endif

    func application(_ application: NSApplication, open urls: [URL]) {
        app.open(urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        app.terminate { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
