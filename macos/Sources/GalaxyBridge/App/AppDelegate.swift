import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.launched()
        #if DEBUG
        if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_MENU"] != nil { showMenuPreview() }
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
