import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppModel()
    private var activityPanel: ActivityPanel?
    private var sendService: SendToGalaxyService?
    private var terminationSignal: DispatchSourceSignal?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if app.mirror.isActive { app.mirror.showWindow() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.launched()
        quitGracefullyOnSIGTERM()
        activityPanel = ActivityPanel(app: app)
        sendService = SendToGalaxyService(app: app)
        NSApp.servicesProvider = sendService
        NSUpdateDynamicServices()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [app] _ in
            MainActor.assumeIsolated { app.systemDidWake() }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_MENU"] != nil { showMenuPreview() }
        if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_CALL"] != nil { app.previewIncomingCall() }
        if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_TRANSFER"] != nil { app.previewTransfer() }
        if ProcessInfo.processInfo.environment["GALAXY_START_MIRROR"] != nil { app.mirror.start() }
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

    private func quitGracefullyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0) }
        source.resume()
        terminationSignal = source
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        app.terminate { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
