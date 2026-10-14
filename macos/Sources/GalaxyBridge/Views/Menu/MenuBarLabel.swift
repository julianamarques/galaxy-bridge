import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "smartphone")
            .onChange(of: app.setupRequested, initial: true) { _, requested in
                guard requested else { return }
                app.setupRequested = false
                openWindow(id: SetupWindow.id)
                NSApp.activate()
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_SETTINGS"] != nil { openSettings() }
            }
            #endif
    }
}
