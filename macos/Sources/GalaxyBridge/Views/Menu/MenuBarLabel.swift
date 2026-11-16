import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: app.transfers.isEmpty ? "smartphone" : "arrow.up.arrow.down")
            .onChange(of: app.setupRequested, initial: true) { _, requested in
                guard requested else { return }
                app.setupRequested = false
                openWindow.activating(id: SetupWindow.id)
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_SETTINGS"] != nil { openSettings() }
            }
            #endif
    }
}
