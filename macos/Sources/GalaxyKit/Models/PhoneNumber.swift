import Foundation

public struct PhoneNumber: Equatable, Sendable {
    public let digits: String

    private static let allowed = Set("0123456789+*#,;")

    public init?(_ text: String) {
        let digits = String(text.filter { Self.allowed.contains($0) })
        guard digits.contains(where: \.isNumber) else { return nil }
        self.digits = digits
    }

    public init?(typed text: String) {
        guard !Self.isName(text) else { return nil }
        self.init(text)
    }

    public static func isName(_ text: String) -> Bool {
        text.contains(where: \.isLetter)
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "tel" else { return nil }
        let text = url.absoluteString.dropFirst("tel:".count)
        let decoded = String(text).removingPercentEncoding ?? String(text)
        let number = decoded.split(separator: ";", maxSplits: 1).first.map(String.init) ?? decoded
        self.init(number)
    }

    public var telURI: String {
        "tel:" + digits.replacingOccurrences(of: "#", with: "%23")
    }
}
