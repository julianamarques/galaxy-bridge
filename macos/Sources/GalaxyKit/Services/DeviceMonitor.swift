import Foundation
import Network

public final class DeviceMonitor: @unchecked Sendable {
    private static let serverPort: NWEndpoint.Port = 5037
    private static let request = Data((String(format: "%04x", "host:track-devices".utf8.count) + "host:track-devices").utf8)
    private static let okay = Array("OKAY".utf8)
    private static let retryDelay: TimeInterval = 2

    private let queue = DispatchQueue(label: "com.julianamarques.GalaxyBridge.devices")
    private var onChange: (@Sendable ([ADBDevice]) -> Void)?
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var acknowledged = false

    public init() {}

    public func start(onChange: @escaping @Sendable ([ADBDevice]) -> Void) {
        guard Tools.find("adb") != nil else { return }
        queue.async {
            self.onChange = onChange
            self.connect()
        }
    }

    public func stop() {
        queue.async {
            self.onChange = nil
            self.connection?.cancel()
            self.connection = nil
        }
    }

    private func connect() {
        Task {
            await ADB.startServer()
            self.queue.async { self.open() }
        }
    }

    private func open() {
        guard onChange != nil, connection == nil else { return }
        let connection = NWConnection(host: .ipv4(.loopback), port: Self.serverPort, using: .tcp)
        self.connection = connection
        buffer = []
        acknowledged = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                connection.send(content: Self.request, completion: .contentProcessed { _ in })
                self.receive(on: connection)
            case .failed, .waiting:
                self.dropped(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, connection === self.connection else { return }
            if let data { buffer.append(contentsOf: data) }
            if !acknowledged, buffer.count >= Self.okay.count {
                guard buffer.starts(with: Self.okay) else { return dropped(connection) }
                buffer.removeFirst(Self.okay.count)
                acknowledged = true
            }
            if acknowledged {
                ADBOutputParser.trackedDeviceLists(consuming: &buffer).forEach { self.onChange?($0) }
            }
            if isComplete || error != nil { return dropped(connection) }
            receive(on: connection)
        }
    }

    private func dropped(_ connection: NWConnection) {
        guard connection === self.connection else { return }
        connection.cancel()
        self.connection = nil
        queue.asyncAfter(deadline: .now() + Self.retryDelay) {
            guard self.onChange != nil, self.connection == nil else { return }
            self.connect()
        }
    }
}
