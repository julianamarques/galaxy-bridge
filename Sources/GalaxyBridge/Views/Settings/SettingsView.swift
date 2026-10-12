import GalaxyKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var isCallHandler = CallLinks.isDefault
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var error: String?
    @State private var confirmingForget = false

    var body: some View {
        Form {
            Section("Galaxy") {
                if app.pairedDevice != nil {
                    LabeledContent("Celular", value: app.deviceName)
                    HStack {
                        if app.pairedDevice?.supportsWiFi == false {
                            Button("Configurar Wi-Fi…") { app.setUpWiFi() }
                        }
                        Spacer()
                        Button("Esquecer Este Galaxy…", role: .destructive) { confirmingForget = true }
                    }
                } else {
                    HStack {
                        Text("Nenhum Galaxy configurado.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Configurar…") {
                            openWindow(id: SetupWindow.id)
                            NSApp.activate()
                        }
                    }
                }
            }

            Section {
                LabeledContent("Links de telefone") {
                    if isCallHandler {
                        Label("Abrem no Galaxy", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Ligar pelo Galaxy") { makeCallHandler() }
                    }
                }
            } header: {
                Text("Ligações")
            } footer: {
                Text("Ao clicar em um número de telefone no Safari, no Contatos, no Calendário ou em outro app, o Galaxy faz a ligação. O áudio continua no celular ou nos fones conectados a ele.")
                    .foregroundStyle(.secondary)
            }

            Section("Geral") {
                Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.set(enabled)
                        } catch {
                            self.error = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        // O formulário agrupado rola e não informa uma altura ideal; sem altura fixa a janela fica baixa demais.
        .frame(width: 460, height: 410)
        .onAppear { isCallHandler = CallLinks.isDefault }
        .confirmationDialog("Esquecer o \(app.deviceName)?", isPresented: $confirmingForget) {
            Button("Esquecer", role: .destructive) { app.forget() }
        } message: {
            Text("Para usá-lo de novo, será preciso configurá-lo outra vez.")
        }
    }

    private func makeCallHandler() {
        Task {
            do {
                try await CallLinks.makeDefault()
            } catch {
                // O usuário pode recusar a troca na janela de confirmação do macOS.
                Log.phone.info("App padrão para tel: não alterado: \(error.localizedDescription, privacy: .public)")
            }
            isCallHandler = CallLinks.isDefault
        }
    }
}
