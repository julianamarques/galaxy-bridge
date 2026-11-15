import GalaxyKit
import SwiftUI

struct TourView: View {
    struct Page {
        let symbol: String
        let tint: Color
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    static let pages: [Page] = [
        Page(
            symbol: "phone.fill", tint: .green, title: "Ligações",
            text: "Atenda e recuse ligações num painel no canto da tela. Para ligar, digite o número ou o nome no menu, ou clique num número no Safari, no Contatos ou em outro app. O som continua no Galaxy ou nos fones conectados a ele."
        ),
        Page(
            symbol: "bell.badge.fill", tint: .red, title: "Notificações e mídia",
            text: "As notificações do Galaxy chegam ao Mac com respostas e imagens. O que está tocando no celular aparece no menu, com os controles. Em Ajustes, escolha os apps que podem notificar no Mac."
        ),
        Page(
            symbol: "photo.on.rectangle.angled", tint: .orange, title: "Fotos e arquivos",
            text: "No menu ficam as fotos e vídeos do Galaxy, as pastas dele e o Tirar Foto, que manda a foto direto para o Mac. Para enviar arquivos ao Galaxy, use Enviar para o Galaxy no Finder ou arraste-os para a janela do espelhamento."
        ),
        Page(
            symbol: "macwindow", tint: .blue, title: "Espelhamento da tela",
            text: "Use o Galaxy numa janela do Mac, com som, mouse e teclado, e copie e cole entre os dois. A cada vez que espelhar, toque na notificação do Galaxy e confirme Iniciar: o Android exige essa confirmação."
        ),
        Page(
            symbol: "cable.connector", tint: .gray, title: "Cabo USB",
            text: "Ligue o Galaxy ao Mac com um cabo para conectar sem Wi-Fi e com menos atraso no espelhamento. Na primeira vez, escolha Sempre na pergunta que aparece no Galaxy."
        ),
    ]

    let index: Int
    let onBack: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        let page = Self.pages[index]
        SetupPage(title: page.title) {
            VStack(spacing: 28) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(page.tint.gradient)
                    .frame(width: 132, height: 132)
                    .overlay {
                        Image(systemName: page.symbol)
                            .font(.system(size: 60, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: page.tint.opacity(0.35), radius: 16, y: 8)
                HStack(spacing: 8) {
                    ForEach(Self.pages.indices, id: \.self) { dot in
                        Circle()
                            .fill(dot == index ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        } content: {
            Text(page.text)
        } buttons: {
            if index > 0 {
                PillButton("Voltar", action: onBack)
            }
            Spacer()
            PillButton("Pular", action: onSkip)
            PillButton("Continuar", prominent: true, action: onContinue)
        }
        .id(index)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
    }
}
