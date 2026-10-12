import Foundation

public struct PhoneNumber: Equatable, Sendable {
    /// Só dígitos e os símbolos aceitos pelo discador (`+`, `*`, `#`, `,`, `;`).
    public let digits: String

    private static let allowed = Set("0123456789+*#,;")

    public init?(_ text: String) {
        let digits = String(text.filter { Self.allowed.contains($0) })
        guard digits.contains(where: \.isNumber) else { return nil }
        self.digits = digits
    }

    /// Aceita `tel:+5511999990000`, `tel://...` e números com espaços ou traços codificados na URL.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "tel" else { return nil }
        let text = url.absoluteString.dropFirst("tel:".count)
        let decoded = String(text).removingPercentEncoding ?? String(text)
        let number = decoded.split(separator: ";", maxSplits: 1).first.map(String.init) ?? decoded
        self.init(number)
    }

    /// URI para a intent do Android. `#` precisa ser codificado, senão vira o fragmento da URI.
    public var telURI: String {
        "tel:" + digits.replacingOccurrences(of: "#", with: "%23")
    }
}
