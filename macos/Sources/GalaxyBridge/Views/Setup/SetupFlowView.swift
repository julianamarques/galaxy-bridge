import AppKit
import GalaxyKit
import SwiftUI

enum SetupWindow {
    static let id = "setup"
}

struct SetupFlowView: View {
    @ObservedObject var setup: SetupModel
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            switch setup.step {
            case .welcome: welcome
            case .appPair: AppPairingView(setup: setup)
            case .missingTools: missingTools
            case .found(let serial, let name): found(serial: serial, name: name)
            case .prepare: prepare
            case .pair: PairingView(setup: setup)
            case .usb: usb
            case .connecting: connecting
            case .failed(let problem): failed(problem)
            case .tour(let index): TourView(index: index, onBack: setup.tourBack, onContinue: setup.tourContinue, onSkip: setup.skipTour)
            case .done: done
            }
        }
        .animation(.easeInOut(duration: 0.25), value: setup.step)
        .onDisappear { setup.windowClosed() }
    }

    private func close() {
        dismissWindow(id: SetupWindow.id)
    }

    private var welcome: some View {
        SetupPage(title: Text(Bundle.appName)) {
            DevicesIllustration()
        } content: {
            Text("Use seu Galaxy junto com o Mac: ligações, notificações, fotos e arquivos, mídia e a tela do celular numa janela, pelo Wi-Fi ou pelo cabo USB.")
        } buttons: {
            PillButton("Saiba Mais…") { openURL(Links.learnMore) }
            Spacer()
            PillButton("Agora Não") { close() }
            PillButton("Continuar", prominent: true) { setup.beginAppPairing() }
        }
    }

    private var missingTools: some View {
        SetupPage(title: "Faltam alguns componentes") {
            DevicesIllustration()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("O \(Bundle.appName) usa o adb, das ferramentas do Android, para se comunicar com o celular. Instale-o pelo Homebrew no Terminal:")
                HStack {
                    Text(installCommand)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copiar") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                    }
                    .font(.body)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        } buttons: {
            PillButton("Saiba Mais…") { openURL(Links.homebrew) }
            Spacer()
            PillButton("Agora Não") { close() }
            PillButton("Tentar Novamente", prominent: true) { setup.continueFromWelcome() }
        }
    }

    private var installCommand: String { "brew install android-platform-tools" }

    private func found(serial: String, name: String) -> some View {
        SetupPage(title: "\(name) encontrado") {
            DevicesIllustration(status: .connected)
        } content: {
            if ADBOutputParser.isUSBSerial(serial) {
                Text("Este Galaxy já está conectado a este Mac pelo cabo USB, por exemplo por outro app. Você pode usá-lo sem parear de novo.")
            } else {
                Text("Este Galaxy já está conectado a este Mac pelo Wi-Fi, por exemplo por outro app. Você pode usá-lo sem parear de novo.")
            }
        } buttons: {
            PillButton("Configurar Outro") { setup.step = .prepare }
            Spacer()
            PillButton("Usar Este Galaxy", prominent: true) { setup.useFound(serial: serial) }
        }
    }

    private var prepare: some View {
        SetupPage(title: "Prepare seu Galaxy") {
            DevicesIllustration()
        } content: {
            NumberedSteps(steps: [
                "Abra **Configurações › Sobre o telefone › Informações do software** e toque 7 vezes em **Número de compilação**.",
                "Volte para **Configurações › Opções do desenvolvedor** e ative a **Depuração sem fio** — ou a **Depuração USB**, se for usar o cabo.",
                "Conecte o Galaxy à mesma rede Wi-Fi deste Mac ou ao Mac com um cabo USB.",
            ])
            .font(.body)
        } buttons: {
            PillButton("Saiba Mais…") { openURL(Links.learnMore) }
            Spacer()
            PillButton("Usar Cabo USB") { setup.beginUSB() }
            PillButton("Usar Wi-Fi", prominent: true) { setup.beginPairing() }
        }
    }

    private var connecting: some View {
        SetupPage(title: "Conectando ao Galaxy…") {
            DevicesIllustration(status: .searching)
        } content: {
            ProgressLabel("Pareamento concluído. Estabelecendo a conexão sem fio.")
        } buttons: {
            Spacer()
            PillButton("Cancelar") { close() }
        }
    }

    private var usb: some View {
        SetupPage(title: "Conectar por cabo USB") {
            DevicesIllustration(status: .searching)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                NumberedSteps(steps: [
                    "Em **Configurações › Opções do desenvolvedor**, ative a **Depuração USB**.",
                    "Conecte o Galaxy a este Mac com um cabo USB.",
                    "No Galaxy, toque em **Permitir** quando aparecer **Permitir depuração USB?**.",
                ])
                .font(.body)
                ProgressLabel(setup.usbStatus == .unauthorized ? "Toque em Permitir no Galaxy…" : "Aguardando o Galaxy no cabo USB…")
                    .font(.callout)
            }
        } buttons: {
            Button("Usar Wi-Fi") { setup.beginPairing() }
                .buttonStyle(.link)
                .controlSize(.regular)
            Spacer()
            PillButton("Cancelar") { close() }
        }
    }

    private func failed(_ problem: ConnectionProblem) -> some View {
        SetupPage(title: Text(problem.title)) {
            DevicesIllustration()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(problem.message)
                if let detail = problem.detail {
                    ErrorDetail(detail)
                }
            }
        } buttons: {
            if problem.needsLocalNetworkPermission {
                PillButton("Abrir Ajustes") { openURL(Links.localNetworkSettings) }
            } else if problem.suggestsUSB {
                PillButton("Usar Cabo USB") { setup.beginUSB() }
            } else {
                PillButton("Saiba Mais…") { openURL(Links.learnMore) }
            }
            Spacer()
            PillButton("Agora Não") { close() }
            PillButton("Tentar Novamente", prominent: true) { setup.retry() }
        }
    }

    private var done: some View {
        SetupPage(title: "Tudo pronto") {
            DevicesIllustration(status: .connected)
        } content: {
            Text("O \(app.deviceName) está conectado. O \(Bundle.appName) fica na barra de menus, com a bateria, as ligações recentes e tudo o que você viu aqui. Para rever esta introdução, abra Ajustes › Sobre.")
        } buttons: {
            SettingsPillLink()
            Spacer()
            PillButton("Começar a Usar", prominent: true) { close() }
        }
    }
}
