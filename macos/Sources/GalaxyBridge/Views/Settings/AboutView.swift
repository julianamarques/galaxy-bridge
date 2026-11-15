import AppKit
import GalaxyKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    private static let repository = URL(string: "https://github.com/julianamarques/galaxy-bridge")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private func showTour() {
        app.setup.showTour()
        openWindow(id: SetupWindow.id)
        NSApp.activate()
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 6)
            Text(Bundle.appName)
                .font(.title2.bold())
            Text("Versão \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text("Seu Galaxy no Mac.")
                Text("Ligações, notificações, arquivos, mídia e espelhamento de tela, direto na barra de menus.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            HStack(spacing: 16) {
                Button("Rever Introdução", action: showTour)
                Link("Ver no GitHub", destination: Self.repository)
            }
            .padding(.top, 12)
            Text(verbatim: "© 2026 Juliana Marques")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .padding(20)
        .frame(width: 460)
    }
}
