import Foundation
import GalaxyKit
import IOUSBHost
import Network

final class AccessoryLink: @unchecked Sendable {
    private enum Kind: UInt8 {
        case open = 0
        case data = 1
        case close = 2
        case pad = 3
        case reset = 4
    }

    private static let headerLength = 7
    private static let readLength = 16 * 1024
    private static let packetSize = 512
    private static let writeTimeout: TimeInterval = 0

    var onClose: (@MainActor () -> Void)?

    private let interface: IOUSBHostInterface
    private let input: IOUSBHostPipe
    private let output: IOUSBHostPipe
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "GalaxyBridge.usb.link")
    private let writeQueue = DispatchQueue(label: "GalaxyBridge.usb.write")
    private var channels: [UInt16: NWConnection] = [:]
    private var buffer = Data()
    private var closed = false

    init(interface: IOUSBHostInterface, port: UInt16) throws {
        self.interface = interface
        guard let input = (0x81...0x8F).lazy.compactMap({ try? interface.copyPipe(withAddress: $0) }).first,
              let output = (0x01...0x0F).lazy.compactMap({ try? interface.copyPipe(withAddress: $0) }).first,
              let port = NWEndpoint.Port(rawValue: port)
        else { throw ToolError.failed("USB") }
        self.input = input
        self.output = output
        self.port = port
    }

    func start() {
        write(.reset, channel: 0, payload: Data())
        Thread.detachNewThread { [self] in read() }
    }

    func close() {
        queue.async { [self] in finish() }
    }

    private func read() {
        guard let data = NSMutableData(length: Self.readLength) else { return close() }
        while true {
            var count: UInt = 0
            do {
                try input.__sendIORequest(with: data, bytesTransferred: &count, completionTimeout: 0)
            } catch {
                return close()
            }
            let chunk = Data(bytes: data.bytes, count: Int(count))
            queue.async { [self] in received(chunk) }
        }
    }

    private func received(_ chunk: Data) {
        guard !closed else { return }
        buffer.append(chunk)
        while buffer.count >= Self.headerLength {
            let bytes = [UInt8](buffer.prefix(Self.headerLength))
            let length = Int(bytes.bigEndian(at: 3, as: UInt32.self))
            guard buffer.count >= Self.headerLength + length else { return }
            let channel = bytes.bigEndian(at: 1, as: UInt16.self)
            let start = buffer.startIndex + Self.headerLength
            let payload = buffer.subdata(in: start..<start + length)
            buffer.removeSubrange(buffer.startIndex..<start + length)
            switch Kind(rawValue: bytes[0]) {
            case .open: open(channel)
            case .data: channels[channel]?.send(content: payload, completion: .idempotent)
            case .close: channels.removeValue(forKey: channel)?.cancel()
            case .pad, .reset, nil: break
            }
        }
    }

    private func open(_ channel: UInt16) {
        let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        channels[channel]?.cancel()
        channels[channel] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled: self.ended(channel, connection)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(channel, connection)
    }

    private func receive(_ channel: UInt16, _ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.readLength) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.write(.data, channel: channel, payload: data) }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(channel, connection)
        }
    }

    private func ended(_ channel: UInt16, _ connection: NWConnection) {
        guard channels[channel] === connection else { return }
        channels[channel] = nil
        write(.close, channel: channel, payload: Data())
    }

    private func write(_ kind: Kind, channel: UInt16, payload: Data) {
        var frame = Self.header(kind, channel: channel, length: payload.count) + payload
        if frame.count % Self.packetSize == 0 { frame += Self.header(.pad, channel: 0, length: 0) }
        writeQueue.async { [self] in
            let data = NSMutableData(data: frame)
            do {
                try output.__sendIORequest(with: data, bytesTransferred: nil, completionTimeout: Self.writeTimeout)
            } catch {
                close()
            }
        }
    }

    private static func header(_ kind: Kind, channel: UInt16, length: Int) -> Data {
        Data([kind.rawValue, UInt8(channel >> 8), UInt8(channel & 0xFF),
              UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)])
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        channels.values.forEach { $0.cancel() }
        channels.removeAll()
        interface.destroy()
        let onClose = onClose
        DispatchQueue.main.async { MainActor.assumeIsolated { onClose?() } }
    }
}
