import SwiftUI

struct QRCodeCard<Overlay: View>: View {
    let payload: String
    let isCovered: Bool
    @ViewBuilder var overlay: Overlay

    var body: some View {
        QRCodeView(payload: payload)
            .frame(width: 210, height: 210)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if isCovered {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay { overlay }
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
