import SwiftUI

struct MirrorMenuItem: View {
    @ObservedObject var mirror: MirrorController
    let deviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: mirror.toggle) {
                HStack {
                    Text(mirror.isActive ? "Parar de Espelhar o \(deviceName)" : "Espelhar a Tela do \(deviceName)")
                    Spacer()
                    if mirror.state == .starting || mirror.state == .reconnecting {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
            .buttonStyle(MenuRowStyle())
            if let message = mirror.error ?? (mirror.isActive ? mirror.hint : nil) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
    }
}
