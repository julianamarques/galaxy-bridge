import GalaxyKit
import SwiftUI

/// O menu da barra de menus, no desenho dos menus do sistema (Wi-Fi, Bluetooth, Bateria):
/// cabeçalho com o aparelho, seções com títulos discretos e linhas de menu no rodapé.
struct MenuView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var number = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !app.isConfigured {
                notConfigured
            } else {
                header
                if case .failed(let problem) = app.connection {
                    problemView(problem)
                }
                MenuDivider()
                dialer
            }
            MenuDivider()
            footer
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: 310)
    }

    // MARK: Aparelho

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DeviceBadge(isConnected: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nenhum Galaxy configurado").font(.headline)
                    Text("Veja a bateria e faça ligações pelo Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button { showSetup() } label: {
                Text("Configurar Galaxy…").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .prominentGlassButtonStyle()
        }
        .padding(.horizontal, 8)
    }

    private var header: some View {
        HStack(spacing: 10) {
            DeviceBadge(isConnected: app.isConnected)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.deviceName).font(.headline)
                status
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let battery = app.battery {
                BatteryLabel(battery: battery)
            }
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var status: some View {
        if app.appPhone != nil {
            if app.isAppConnected {
                Label("Wi-Fi", systemImage: "wifi")
            } else {
                Text("Desconectado")
            }
        } else {
            adbStatus
        }
    }

    @ViewBuilder
    private var adbStatus: some View {
        switch app.connection {
        case .idle, .failed:
            Text("Desconectado")
        case .connecting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Procurando…")
            }
        case .connected(let serial):
            if ADBOutputParser.isUSBSerial(serial) {
                Label("Cabo USB", systemImage: "cable.connector")
            } else {
                Label("Wi-Fi", systemImage: "wifi")
            }
        }
    }

    private func problemView(_ problem: ConnectionProblem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title).font(.subheadline.weight(.semibold))
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            Button("Tentar Novamente") { app.reconnect() }
                .buttonStyle(MenuRowStyle())
        }
    }

    // MARK: Ligações

    private var dialer: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSectionTitle("Ligar pelo Galaxy")
            HStack(spacing: 8) {
                PhoneField(
                    placeholder: String(localized: "Número de telefone"),
                    text: $number,
                    country: app.dialCountry,
                    onSubmit: call
                )
                CircleButton(systemImage: "phone.fill", tint: .green, help: "Ligar", action: call)
                    .disabled(PhoneNumber(number) == nil)
                CircleButton(systemImage: "phone.down.fill", tint: .red, help: "Encerrar a ligação") { app.endCall() }
                    .disabled(!app.canEndCall)
            }
            if let error = app.callError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: Rodapé

    private var footer: some View {
        VStack(spacing: 0) {
            SettingsLink { Text("Ajustes do \(Bundle.appName)…") }
                .buttonStyle(MenuRowStyle())
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            Button("Sair do \(Bundle.appName)") { NSApp.terminate(nil) }
                .buttonStyle(MenuRowStyle())
        }
    }

    private func call() {
        guard let phone = PhoneNumber(number) else { return }
        app.call(phone)
    }

    private func showSetup() {
        openWindow(id: SetupWindow.id)
        NSApp.activate()
    }
}

// MARK: - Componentes

/// O ícone do aparelho num círculo, preenchido com a cor de destaque quando ele está conectado,
/// como os aparelhos no menu Bluetooth.
private struct DeviceBadge: View {
    let isConnected: Bool

    var body: some View {
        Image(systemName: "smartphone")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isConnected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: 32, height: 32)
            .background(
                Circle().fill(isConnected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            )
    }
}

private struct MenuSectionTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8)
    }
}

/// Botão redondo de ligação, sempre verde ou vermelho como os do FaceTime (a cor não depende da janela estar ativa).
private struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(CallButtonStyle(tint: tint))
        .help(help)
    }
}

private struct CallButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        CallButton(configuration: configuration, tint: tint)
    }

    private struct CallButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.gradient))
                .glassCircle()
                .brightness(configuration.isPressed ? -0.15 : 0)
                .opacity(isEnabled ? 1 : 0.35)
                .contentShape(Circle())
        }
    }
}

private extension View {
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
        }
    }
}

/// Uma linha de menu: ocupa a largura toda e ganha um destaque arredondado com o ponteiro em cima.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : isHovered && isEnabled ? 0.09 : 0))
                )
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

private struct BatteryLabel: View {
    let battery: Battery

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: "\(battery.level)%")
                .monospacedDigit()
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15))
        }
        .font(.subheadline)
        .foregroundStyle(isLow ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        .help(battery.isCharging ? "Carregando" : "Bateria")
    }

    private var isLow: Bool { battery.level <= 20 && !battery.isCharging }

    private var symbol: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
