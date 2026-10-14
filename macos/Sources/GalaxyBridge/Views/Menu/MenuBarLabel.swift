import SwiftUI

/// O ícone na barra de menus. Também abre a janela de configuração quando o `AppModel` pede,
/// porque o `openWindow` só existe dentro de uma cena e esta é a única que está sempre carregada.
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
                // Abre os Ajustes ao iniciar, para conferir o visual sem clicar no menu.
                if ProcessInfo.processInfo.environment["GALAXY_PREVIEW_SETTINGS"] != nil { openSettings() }
            }
            #endif
    }
}
