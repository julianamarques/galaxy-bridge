import BridgeProtocol
import SwiftUI

struct PhoneStatusBar: View {
    @EnvironmentObject private var app: AppModel
    let status: PhoneStatus

    var body: some View {
        HStack(spacing: 12) {
            if status.signal != nil || status.carrier != nil {
                Label {
                    Text(verbatim: [status.carrier, status.network].compactMap { $0 }.joined(separator: " "))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "cellularbars", variableValue: level(status.signal))
                }
                .help("Sinal da operadora")
            }
            if let wifi = status.wifi {
                Image(systemName: "wifi", variableValue: level(wifi))
                    .help("Conectado ao Wi-Fi")
            }
            if let storage = status.storage {
                Label {
                    Text("\(storage.free.formatted(.byteCount(style: .file))) livres")
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "internaldrive")
                }
                .help("Armazenamento livre no \(app.deviceName), de \(storage.total.formatted(.byteCount(style: .file)))")
            }
            Spacer(minLength: 0)
            if let dnd = status.dnd {
                Button {
                    app.setDoNotDisturb(!dnd)
                } label: {
                    Image(systemName: dnd ? "moon.fill" : "moon")
                        .foregroundStyle(dnd ? AnyShapeStyle(.indigo) : AnyShapeStyle(.secondary))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(dnd ? "Desativar o Não Perturbe no \(app.deviceName)" : "Ativar o Não Perturbe no \(app.deviceName)")
            }
        }
        .labelStyle(StatusLabelStyle())
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func level(_ value: Int?) -> Double {
        Double(value ?? 0) / 4
    }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
