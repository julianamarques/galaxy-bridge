import Foundation

public struct ADBDevice: Equatable, Sendable {
    public let serial: String
    public let state: String

    public var isReady: Bool { state == "device" }
    public var isUSB: Bool { ADBOutputParser.isUSBSerial(serial) }
}
