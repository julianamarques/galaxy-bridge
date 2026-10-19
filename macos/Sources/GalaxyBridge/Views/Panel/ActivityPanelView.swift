import BridgeProtocol
import SwiftUI

struct ActivityPanelView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject var panel: ActivityPanel

    var body: some View {
        VStack(spacing: 10) {
            if let call = panel.visibleCall {
                PanelCard { panel.hide(call.call) } content: { CallCard(call: call) }
            }
            ForEach(panel.visibleTransfers) { transfer in
                PanelCard { panel.hide(transfer.id) } content: { TransferCard(transfer: transfer) }
            }
        }
        .padding(12)
    }
}

private struct PanelCard<Content: View>: View {
    let onHide: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovering = false

    var body: some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(width: 340)
            .panelBackground()
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .overlay(alignment: .topLeading) { hideButton }
            .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var hideButton: some View {
        if isHovering {
            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.regularMaterial))
                    .overlay(Circle().strokeBorder(.separator))
            }
            .buttonStyle(.plain)
            .help("Ocultar")
            .offset(x: -6, y: -6)
        }
    }
}

private struct CallCard: View {
    @EnvironmentObject private var app: AppModel
    let call: CallState

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(name: call.name, photo: call.contact.flatMap { app.photos[$0] }, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.callerName)
                    .font(.headline)
                    .lineLimit(1)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if call.state == .ringing {
                CircleButton(systemImage: "phone.fill", tint: .green, help: "Atender", size: 40) { app.answerCall() }
                CircleButton(systemImage: "phone.down.fill", tint: .red, help: "Recusar", size: 40) { app.declineCall() }
            } else {
                CircleButton(systemImage: "phone.down.fill", tint: .red, help: "Encerrar a ligação", size: 40) { app.endCall() }
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if call.state == .ringing {
            Text(call.name == nil ? "Ligação no \(app.deviceName)" : app.callerNumber ?? "Ligação no \(app.deviceName)")
        } else if let answeredAt = app.callAnsweredAt {
            TimelineView(.periodic(from: answeredAt, by: 1)) { context in
                Text(Self.duration(from: answeredAt, to: context.date) + " · " + app.deviceName)
                    .monospacedDigit()
            }
        } else {
            Text("Ligando pelo \(app.deviceName)")
        }
    }

    private static func duration(from start: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }
}

private struct TransferCard: View {
    @EnvironmentObject private var app: AppModel
    let transfer: TransferProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transfer.direction == .toPhone ? "arrow.up" : "arrow.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 5) {
                Text(transfer.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack {
                    Text(transfer.direction == .toPhone ? "Enviando para o \(app.deviceName)" : "Recebendo do \(app.deviceName)")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(status)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                ProgressView(value: transfer.fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        }
    }

    private var status: String {
        if transfer.done == 0, transfer.direction == .toPhone { return String(localized: "Aguardando…") }
        return transfer.fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

private extension View {
    @ViewBuilder
    func panelBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.separator))
        }
    }
}
