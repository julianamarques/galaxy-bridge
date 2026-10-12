import GalaxyKit
import SwiftUI

@main
struct SamsungForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(delegate.app)
        } label: {
            MenuBarLabel()
                .environmentObject(delegate.app)
        }
        .menuBarExtraStyle(.window)

        Window(Bundle.appName, id: SetupWindow.id) {
            SetupFlowView(setup: delegate.app.setup)
                .environmentObject(delegate.app)
                .frame(width: 680, height: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(delegate.app)
        }
    }
}
