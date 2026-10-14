import Foundation
import Security

public struct PairedPhone: Codable, Equatable, Identifiable, Sendable {
    public var fingerprint: String
    public var name: String
    public var model: String
    public var pairedAt: Date

    public var id: String { fingerprint }

    public init(fingerprint: String, name: String, model: String, pairedAt: Date = Date()) {
        self.fingerprint = fingerprint
        self.name = name
        self.model = model
        self.pairedAt = pairedAt
    }
}

@MainActor
public final class PairingStore {
    public private(set) var phones: [PairedPhone]
    private let file: URL?

    public init(file: URL?) {
        self.file = file
        phones = file
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([PairedPhone].self, from: $0) } ?? []
    }

    public func phone(withFingerprint fingerprint: String) -> PairedPhone? {
        phones.first { $0.fingerprint == fingerprint }
    }

    public func save(_ phone: PairedPhone) {
        phones.removeAll { $0.fingerprint == phone.fingerprint }
        phones.append(phone)
        write()
    }

    public func remove(fingerprint: String) {
        phones.removeAll { $0.fingerprint == fingerprint }
        write()
    }

    private func write() {
        guard let file, let data = try? JSONEncoder().encode(phones) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

public struct PairingSession: Sendable {
    public static let lifetime: TimeInterval = 120
    public static let maxCodeAttempts = 5

    public let token: String
    public let code: String
    public let expiresAt: Date
    private(set) var failedAttempts = 0

    public enum Check: Equatable {
        case accepted
        case invalid
        case expired
    }

    public init(now: Date = Date()) {
        token = Self.randomToken()
        code = String(format: "%06d", Int.random(in: 0...999_999))
        expiresAt = now.addingTimeInterval(Self.lifetime)
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt || failedAttempts >= Self.maxCodeAttempts
    }

    public mutating func check(_ secret: String, now: Date = Date()) -> Check {
        guard !isExpired(now: now) else { return .expired }
        if constantTimeEquals(secret, token) || constantTimeEquals(secret, code) { return .accepted }
        failedAttempts += 1
        return isExpired(now: now) ? .expired : .invalid
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let a = Array(a.utf8), b = Array(b.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public struct PairingLink: Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var fingerprint: String
    public var token: String

    public init(host: String, port: UInt16, fingerprint: String, token: String) {
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
        self.token = token
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "galaxybridge"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(protocolVersion)),
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "fp", value: fingerprint),
            URLQueryItem(name: "token", value: token),
        ]
        return components.url!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "galaxybridge", components.host == "pair"
        else { return nil }
        let items = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        guard items["v"] == String(protocolVersion),
              let host = items["host"], !host.isEmpty,
              let port = items["port"].flatMap(UInt16.init),
              let fingerprint = items["fp"], fingerprint.count == 64,
              let token = items["token"], !token.isEmpty
        else { return nil }
        self.init(host: host, port: port, fingerprint: fingerprint, token: token)
    }
}
