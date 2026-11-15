import GalaxyKit
import SwiftUI

@main
struct GalaxyBridgeApp: App {
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

        Window(String(localized: "Arquivos do Galaxy"), id: FileBrowser.windowID) {
            FileBrowserView(browser: delegate.app.fileBrowser)
                .environmentObject(delegate.app)
        }
        .defaultSize(width: 720, height: 480)

        Settings {
            TabView {
                SettingsView()
                    .environmentObject(delegate.app)
                    .tabItem { Label("Geral", systemImage: "gearshape") }
                AboutView()
                    .tabItem { Label("Sobre", systemImage: "info.circle") }
            }
        }
    }
}
