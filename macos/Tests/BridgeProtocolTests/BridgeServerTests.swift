import Foundation
import Network
import Testing
@testable import BridgeProtocol

@MainActor
@Suite(.serialized)
struct BridgeServerTests {
    let server: BridgeServer
    let events = EventLog()

    init() throws {
        server = BridgeServer(
            identity: try Identity.ephemeral(name: "Mac de teste"),
            store: PairingStore(file: nil),
            hello: Hello(appVersion: "test", name: "Mac de teste", model: "Mac")
        )
        server.onEvent = { [events] in events.append($0) }
    }

    private func start() async throws -> UInt16 {
        server.start(port: nil)
        try await until { server.port != nil }
        return server.port!
    }

    @Test func pairsWithTheQRToken() async throws {
        let port = try await start()
        let session = server.beginPairing()
        let phone = try TestPhone()
        try await phone.connect(port: port, pinning: server.identity.fingerprint)

        phone.send(Envelope(.hello(phone.hello)))
        phone.send(Envelope(.pairRequest(PairRequest(secret: session.token, name: "Galaxy S25", model: "SM-S931B"))))
        #expect(try await phone.next() == .pairAccepted(PairAccepted(name: "Mac de teste")))
        #expect(try await phone.next() == .hello(Hello(appVersion: "test", name: "Mac de teste", model: "Mac")))

        #expect(server.store.phones.map(\.fingerprint) == [phone.identity.fingerprint])
        #expect(server.phone?.name == "Galaxy S25")
        #expect(server.pairing == nil)

        let status = PhoneStatus(battery: .init(level: 71, charging: false), networkCountry: "BR")
        phone.send(Envelope(.status(status)))
        try await until { events.contains { if case .status(status) = $0 { true } else { false } } }

        let id = server.send(.callPlace(CallPlace(number: "+5586999990001")))
        #expect(id != nil)
        #expect(try await phone.next() == .callPlace(CallPlace(number: "+5586999990001")))
        phone.close()
    }

    @Test func reconnectsAPairedPhoneWithoutPairing() async throws {
        let port = try await start()
        let phone = try TestPhone()
        server.store.save(PairedPhone(fingerprint: phone.identity.fingerprint, name: "Antigo", model: "SM-S931B"))

        try await phone.connect(port: port, pinning: server.identity.fingerprint)
        phone.send(Envelope(.hello(phone.hello)))
        guard case .hello = try await phone.next() else { Issue.record("sem hello"); return }
        #expect(server.store.phones.first?.name == "Galaxy S25")

        phone.send(Envelope(.ping, id: "p"))
        #expect(try await phone.next() == .pong)
        phone.close()
        try await until { server.phone == nil }
    }

    @Test func refusesUnknownPhoneWhenNotPairing() async throws {
        let port = try await start()
        let phone = try TestPhone()
        try? await phone.connect(port: port, pinning: server.identity.fingerprint)
        phone.send(Envelope(.hello(phone.hello)))
        await #expect(throws: (any Error).self) { try await phone.next() }
        #expect(server.phone == nil)
    }

    @Test func rejectsWrongCode() async throws {
        let port = try await start()
        let session = server.beginPairing()
        let phone = try TestPhone()
        try await phone.connect(port: port, pinning: server.identity.fingerprint)
        let wrong = session.code == "000000" ? "000001" : "000000"
        phone.send(Envelope(.hello(phone.hello)))
        phone.send(Envelope(.pairRequest(PairRequest(secret: wrong, name: "Intruso", model: "X"))))
        #expect(try await phone.next() == .pairRejected(PairRejected(reason: .invalid)))
        #expect(server.store.phones.isEmpty)
        #expect(server.pairing != nil)
    }

    @Test func phoneRefusesAnotherMac() async throws {
        let port = try await start()
        let phone = try TestPhone()
        await #expect(throws: (any Error).self) {
            try await phone.connect(port: port, pinning: String(repeating: "0", count: 64))
        }
    }

    @Test func refusesOtherProtocolVersion() async throws {
        let port = try await start()
        let phone = try TestPhone()
        server.store.save(PairedPhone(fingerprint: phone.identity.fingerprint, name: "Galaxy", model: "X"))
        try await phone.connect(port: port, pinning: server.identity.fingerprint)
        var hello = phone.hello
        hello.version = 2
        phone.send(Envelope(.hello(hello)))
        guard case .error(let error) = try await phone.next() else { Issue.record("sem erro"); return }
        #expect(error.code == .version)
    }

    @Test func forgetTellsThePhone() async throws {
        let port = try await start()
        let phone = try TestPhone()
        let paired = PairedPhone(fingerprint: phone.identity.fingerprint, name: "Galaxy", model: "X")
        server.store.save(paired)
        try await phone.connect(port: port, pinning: server.identity.fingerprint)
        phone.send(Envelope(.hello(phone.hello)))
        _ = try await phone.next()

        server.forget(paired)
        #expect(try await phone.next() == .unpair)
        #expect(server.store.phones.isEmpty)
        try await until { events.contains { if case .disconnected = $0 { true } else { false } } }
    }
}

@MainActor
final class EventLog {
    private(set) var events: [BridgeServer.Event] = []
    func append(_ event: BridgeServer.Event) { events.append(event) }
    func contains(where predicate: (BridgeServer.Event) -> Bool) -> Bool { events.contains(where: predicate) }
}

struct Timeout: Error {}

@MainActor
func until(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw Timeout() }
        try await Task.sleep(for: .milliseconds(20))
    }
}

final class TestPhone: @unchecked Sendable {
    let identity: Identity
    let hello = Hello(appVersion: "test", name: "Galaxy S25", model: "SM-S931B")
    private let queue = DispatchQueue(label: "test-phone")
    private var connection: NWConnection?
    private var decoder = FrameDecoder()
    private var received: [Message] = []
    private var failed = false
    private let lock = NSLock()

    init() throws {
        identity = try Identity.ephemeral(name: "Galaxy de teste")
    }

    func connect(port: UInt16, pinning fingerprint: String) async throws {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_local_identity(options, sec_identity_create(identity.secIdentity)!)
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let trust = sec_trust_copy_ref(trust).takeRetainedValue()
            let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
            complete(leaf.map { Fingerprint.of(SecCertificateCopyData($0) as Data) } == fingerprint)
        }, queue)
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: tls))
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: resumed.run { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    self.markFailed()
                    resumed.run { continuation.resume(throwing: error) }
                case .cancelled:
                    self.markFailed()
                    resumed.run { continuation.resume(throwing: Timeout()) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
        receive()
    }

    func send(_ envelope: Envelope) {
        connection?.send(content: try! Frame.encode(envelope), completion: .idempotent)
    }

    func next(timeout: Duration = .seconds(5)) async throws -> Message {
        let deadline = ContinuousClock.now + timeout
        while true {
            let (message, isFailed) = lock.withLock { (received.isEmpty ? nil : received.removeFirst(), failed) }
            if let message { return message }
            if isFailed || ContinuousClock.now >= deadline { throw Timeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func close() {
        connection?.cancel()
    }

    private func markFailed() {
        lock.withLock { failed = true }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data {
                let bodies = self.lock.withLock { (try? self.decoder.append(data)) ?? [] }
                let messages = bodies.compactMap { try? JSONDecoder().decode(Envelope.self, from: $0).message }
                self.lock.withLock { self.received += messages }
            }
            if isComplete || error != nil { return self.markFailed() }
            self.receive()
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ action: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { action() }
    }
}
