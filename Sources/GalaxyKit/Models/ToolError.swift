import Foundation

public enum ToolError: LocalizedError, Equatable, Sendable {
    case missing(String)
    case failed(String)
    case timeout
    case phoneHotspot
    case differentNetwork(mac: String?, phone: String)
    case usbNotConnected
    case mirrorTimeout
    case localNetworkDenied

    public var errorDescription: String? {
        switch self {
        case .missing(let name): String(localized: "O componente “\(name)” não foi encontrado.")
        case .failed(let message): message
        case .timeout: String(localized: "O Galaxy não respondeu a tempo.")
        case .phoneHotspot: String(localized: "O Mac está conectado ao hotspot do Galaxy.")
        case .differentNetwork(_, let phone): String(localized: "O Galaxy (\(phone)) está em outra rede.")
        case .usbNotConnected: String(localized: "O Galaxy não está conectado por cabo USB.")
        case .mirrorTimeout: String(localized: "O Galaxy não começou a enviar a imagem.")
        case .localNetworkDenied: String(localized: "O macOS não permitiu que o \(Bundle.appName) acesse a rede local.")
        }
    }
}
