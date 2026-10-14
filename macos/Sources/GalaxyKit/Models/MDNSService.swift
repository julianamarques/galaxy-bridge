import Foundation

public struct MDNSService: Equatable, Identifiable, Sendable {
    public static let pairingType = "_adb-tls-pairing._tcp"
    public static let connectType = "_adb-tls-connect._tcp"

    public let name: String
    public let type: String
    public let address: String

    public var id: String { name + type }
    public var host: String { ADBOutputParser.host(of: address) }
}
