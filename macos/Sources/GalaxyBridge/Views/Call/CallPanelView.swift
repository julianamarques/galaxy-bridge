import BridgeProtocol
import SwiftUI

struct CallPanelView: View {
    @EnvironmentObject private var app: AppModel
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        if let call = app.call {
            content(for: call)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .frame(width: 340)
                .panelBackground()
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .overlay(alignment: .topLeading) { closeButton }
                .onHover { isHovering = $0 }
                .padding(12)
        }
    }

    private func content(for call: CallState) -> some View {
        HStack(spacing: 12) {
            CallerAvatar(name: call.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.callerName)
                    .font(.headline)
                    .lineLimit(1)
                subtitle(for: call)
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
    private func subtitle(for call: CallState) -> some View {
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

    @ViewBuilder
    private var closeButton: some View {
        if isHovering {
            Button(action: onClose) {
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

    private static func duration(from start: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }
}

private struct CallerAvatar: View {
    let name: String?

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
            if let initials {
                Text(initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 40, height: 40)
    }

    private var initials: String? {
        guard let name, name.first?.isLetter == true else { return nil }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
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
