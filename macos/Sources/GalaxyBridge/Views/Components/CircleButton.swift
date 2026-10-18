import SwiftUI

struct CircleButton: View {
    let systemImage: String
    let tint: Color
    let help: LocalizedStringKey
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(CallButtonStyle(tint: tint, size: size))
        .help(help)
    }
}

private struct CallButtonStyle: ButtonStyle {
    let tint: Color
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        CallButton(configuration: configuration, tint: tint, size: size)
    }

    private struct CallButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
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
