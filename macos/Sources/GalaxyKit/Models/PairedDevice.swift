import Foundation

public struct PairedDevice: Codable, Equatable, Sendable {
    public var guid: String?
    public var name: String
    public var lastAddress: String?
    public var usbSerial: String?

    public init(guid: String?, name: String, lastAddress: String?, usbSerial: String?) {
        self.guid = guid
        self.name = name
        self.lastAddress = lastAddress
        self.usbSerial = usbSerial
    }

    public var supportsWiFi: Bool { guid != nil || lastAddress != nil }

    public func matchesUSB(_ serial: String) -> Bool {
        usbSerial == serial || guid?.hasPrefix("adb-\(serial)-") == true
    }

    public func matches(_ serial: String) -> Bool {
        if ADBOutputParser.isUSBSerial(serial) { return matchesUSB(serial) }
        if let guid, serial.hasPrefix(guid) { return true }
        guard let lastAddress else { return false }
        return serial.hasPrefix(ADBOutputParser.host(of: lastAddress) + ":")
    }
}
