import SwiftUI

extension View {
    func pillStyle() -> some View {
        controlSize(.extraLarge).buttonBorderShape(.capsule)
    }

    @ViewBuilder
    func pillButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(ProminentPillStyle())
        } else if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

extension View {
    /// Botão de vidro com a cor de destaque (ou a de `.tint`) no macOS 26 e posteriores.
    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
