import SwiftUI

/// O Mac e o Galaxy lado a lado, ligados por uma linha que pulsa enquanto o app procura o celular.
struct DevicesIllustration: View {
    enum Status { case idle, searching, connected }

    var status: Status = .idle

    var body: some View {
        HStack(spacing: 28) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 150, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Link(status: status)
                .frame(width: 90)
            GalaxyPhone(connected: status == .connected)
        }
        .frame(width: 560, height: 266)
    }
}

private struct Link: View {
    let status: DevicesIllustration.Status
    @State private var phase = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(status == .idle ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor))
                    .frame(width: 7, height: 7)
                    .opacity(status == .searching ? (phase ? 1 : 0.2) : 1)
                    .animation(
                        status == .searching
                            ? .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.12)
                            : .default,
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
