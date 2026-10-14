import SwiftUI

/// O pareamento com o app Galaxy Bridge no celular: o Mac mostra o QR code, e o celular o escaneia
/// (ou digita o código de seis dígitos e confere a impressão digital do Mac).
struct AppPairingView: View {
    @ObservedObject var setup: SetupModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        SetupPage(title: "Escaneie com o Galaxy") {
            qrCode
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                NumberedSteps(steps: [
                    "Instale o app **Galaxy Bridge** no Galaxy e abra-o.",
                    "Toque em **Escanear código do Mac** e aponte a câmera para o código acima.",
                ])
                .font(.body)
                if let problem = setup.appPairingProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.primary)
                } else {
                    Text("Sem câmera? Toque em **Digitar código**, use **\(setup.appCode)** e confira se o celular mostra **\(setup.macFingerprint)**.")
                        .font(.callout)
                }
            }
        } buttons: {
            Button("Usar a depuração do Android") { setup.useAndroidDebugging() }
                .buttonStyle(.link)
                .controlSize(.regular)
            Spacer()
            PillButton("Cancelar") { dismissWindow(id: SetupWindow.id) }
        }
    }

    private var qrCode: some View {
        QRCodeView(payload: setup.appLink ?? "")
            .frame(width: 210, height: 210)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if setup.appLink == nil {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            if setup.appPairingProblem == nil { ProgressView() }
                        }
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
