import BridgeProtocol
import GalaxyKit
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var number = ""
    @State private var selectedSuggestion: Int?

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
                if !app.transfers.isEmpty {
                    MenuDivider()
                    transfers
                }
            }
            MenuDivider()
            footer
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: 310)
    }

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
        if let call = app.call {
            Label(callStatus(call), systemImage: "phone.fill")
                .foregroundStyle(.green)
        } else if app.appPhone != nil {
            if app.isAppConnected {
                Label("Wi-Fi", systemImage: "wifi")
            } else {
                Text("Desconectado")
            }
        } else {
            adbStatus
        }
    }

    private func callStatus(_ call: CallState) -> String {
        switch call.state {
        case .ringing: String(localized: "\(app.callerName) está ligando")
        case .active: String(localized: "Em ligação com \(app.callerName)")
        case .voicemail: String(localized: "\(app.callerName) no correio de voz")
        case .ended: ""
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

    private var dialer: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSectionTitle("Ligar pelo Galaxy")
            HStack(spacing: 8) {
                PhoneField(
                    placeholder: app.appPhone == nil ? String(localized: "Número de telefone") : String(localized: "Nome ou número"),
                    text: $number,
                    country: app.dialCountry,
                    onSubmit: call,
                    onMove: moveSelection
                )
                CircleButton(systemImage: "phone.fill", tint: .green, help: "Ligar", action: call)
                    .disabled(target == nil)
                CircleButton(systemImage: "phone.down.fill", tint: .red, help: "Encerrar a ligação") { app.endCall() }
                    .disabled(!app.canEndCall)
            }
            if !app.contactSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(app.contactSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        SuggestionRow(suggestion: suggestion, photo: app.photos[suggestion.contact.id], isSelected: index == selectedSuggestion) {
                            dial(PhoneNumber(suggestion.number.number))
                        }
                    }
                }
                .padding(.horizontal, -8)
            } else if let error = app.contactsError, PhoneNumber.isName(number) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = app.callError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .onChange(of: number) { _, query in
            selectedSuggestion = nil
            app.searchContacts(query)
        }
    }

    private var target: PhoneNumber? {
        let suggestions = app.contactSuggestions
        if let index = selectedSuggestion, suggestions.indices.contains(index) {
            return PhoneNumber(suggestions[index].number.number)
        }
        return PhoneNumber(typed: number) ?? suggestions.first.flatMap { PhoneNumber($0.number.number) }
    }

    private func moveSelection(_ step: Int) {
        let count = app.contactSuggestions.count
        guard count > 0 else { return }
        let next = (selectedSuggestion ?? -1) + step
        selectedSuggestion = next < 0 ? nil : min(next, count - 1)
    }

    private func dial(_ phone: PhoneNumber?) {
        guard let phone else { return }
        app.call(phone)
        number = ""
    }

    private var transfers: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSectionTitle("Transferências")
            ForEach(app.transfers) { transfer in
                HStack(spacing: 8) {
                    Image(systemName: transfer.direction == .toPhone ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(.secondary)
                        .help(transfer.label(device: app.deviceName))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(transfer.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(transfer.status)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        ProgressView(value: transfer.fraction)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if app.appPhone != nil {
                Button("Enviar Arquivo para o \(app.deviceName)…") { app.chooseFilesToSend() }
                    .buttonStyle(MenuRowStyle())
                    .disabled(!app.isAppConnected)
                Button("Enviar Texto Copiado para o \(app.deviceName)") { app.sendClipboard() }
                    .buttonStyle(MenuRowStyle())
                    .disabled(!app.isAppConnected)
            }
            SettingsLink { Text("Ajustes do \(Bundle.appName)…") }
                .buttonStyle(MenuRowStyle())
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            Button("Sair do \(Bundle.appName)") { NSApp.terminate(nil) }
                .buttonStyle(MenuRowStyle())
        }
    }

    private func call() {
        dial(target)
    }

    private func showSetup() {
        openWindow(id: SetupWindow.id)
        NSApp.activate()
    }
}

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

struct MenuRowStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration, isSelected: isSelected)
    }

    private struct MenuRow: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
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
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(configuration.isPressed ? 0.16 : isHovered && isEnabled ? 0.09 : 0))
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

private struct SuggestionRow: View {
    let suggestion: ContactSuggestion
    let photo: NSImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ContactAvatar(name: suggestion.contact.name, photo: photo, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.contact.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(MenuRowStyle(isSelected: isSelected))
    }
}
