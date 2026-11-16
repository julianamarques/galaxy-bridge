import Foundation
import Network

@MainActor
final class BridgeConnection {
    let connection: NWConnection
    private(set) var fingerprint: String?
    var hello: Hello?
    var phone: PairedPhone?
    var transfer: TransferSession?
    private(set) var lastPing = Date()
    private(set) var awaitingPong = false
    private var decoder = FrameDecoder()
    private var isClosed = false
    private var whenCancelled: (@MainActor () -> Void)?

    var onMessage: ((Envelope) -> Void)?
    var onRawFrame: ((Data) -> Void)? {
        didSet { decoder.maxLength = onRawFrame == nil ? Frame.maxLength : Frame.maxVideoLength }
    }
    var onClose: (() -> Void)?

    var host: String? {
        guard case .hostPort(let host, _) = connection.endpoint else { return nil }
        let text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): text = name
        @unknown default: return nil
        }
        return String(text.split(separator: "%").first ?? "").replacingOccurrences(of: "::ffff:", with: "")
    }

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.stateChanged(state) }
        }
        connection.start(queue: .main)
    }

    func send(_ envelope: Envelope, then completion: (@MainActor () -> Void)? = nil) {
        guard !isClosed, let data = try? Frame.encode(envelope) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in
            guard let completion else { return }
            MainActor.assumeIsolated { completion() }
        })
    }

    func ping(at date: Date) {
        lastPing = date
        awaitingPong = true
        send(Envelope(.ping))
    }

    func finish(then completion: @escaping @MainActor () -> Void) {
        guard !isClosed else { return completion() }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return completion() }
                self.whenCancelled = completion
                self.close()
            }
        })
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
        onClose?()
    }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            fingerprint = Self.peerFingerprint(of: connection)
            guard fingerprint != nil else { return close() }
            receive()
        case .waiting:
            close()
        case .failed, .cancelled:
            close()
            let done = whenCancelled
            whenCancelled = nil
            done?()
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    self.awaitingPong = false
                    do {
                        for body in try self.decoder.append(data) {
                            if let raw = self.onRawFrame {
                                raw(body)
                                continue
                            }
                            guard let envelope = try? Frame.decoder.decode(Envelope.self, from: body) else { continue }
                            self.onMessage?(envelope)
                            if self.isClosed { return }
                        }
                    } catch {
                        return self.close()
                    }
                }
                if isComplete || error != nil { return self.close() }
                self.receive()
            }
        }
    }

    nonisolated static func peerFingerprint(of connection: NWConnection) -> String? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return nil
        }
        let chain = CertificateChain()
        _ = sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
            chain.append(SecCertificateCopyData(sec_certificate_copy_ref(certificate).takeRetainedValue()) as Data)
        }
        return chain.first.map(Fingerprint.of)
    }
}

private final class CertificateChain: @unchecked Sendable {
    private(set) var first: Data?

    func append(_ certificate: Data) {
        if first == nil { first = certificate }
    }
}
