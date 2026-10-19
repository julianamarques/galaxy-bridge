import Foundation
import Network
import UniformTypeIdentifiers
import OSLog

@MainActor
public final class BridgeServer {
    public enum Event: Sendable {
        case ready
        case failed(String)
        case connected(PairedPhone)
        case disconnected
        case paired(PairedPhone)
        case pairingExpired
        case unpaired
        case status(PhoneStatus)
        case call(CallState)
        case contacts(ContactResults, replyTo: String?)
        case photo(ContactPhoto)
        case notificationPosted(PhoneNotification)
        case notificationRemoved(String)
        case notificationsActive([String])
        case fileReceived(URL, name: String)
        case fileSent(name: String, ok: Bool)
        case transferProgress(TransferProgress)
        case transferEnded(String)
        case clipboard(String)
        case error(BridgeError, replyTo: String?)
    }

    public static let serviceType = "_galaxybridge._tcp"
    public static let preferredPort: UInt16 = 52800
    public static let pingInterval: TimeInterval = 120
    public static let pongTimeout: TimeInterval = 60
    static let keepAliveCheckInterval: TimeInterval = 15
    static let setupTimeout: TimeInterval = 30

    public let identity: Identity
    public let store: PairingStore
    public var onEvent: ((Event) -> Void)?
    public private(set) var port: UInt16?
    public private(set) var pairing: PairingSession?
    public var phone: PairedPhone? { active?.phone }

    private let hello: Hello
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: BridgeConnection] = [:]
    private var active: BridgeConnection?
    private var timer: Timer?
    private var pairingTimer: Timer?
    private var wakeMonitor: NWPathMonitor?
    private var nextID = 0
    private var incoming: [ObjectIdentifier: IncomingTransfer] = [:]
    private var offered: [String: OutgoingTransfer] = [:]
    private var sending: [ObjectIdentifier: String] = [:]
    static let offerTimeout: Duration = .seconds(60)
    private var activities: [ObjectIdentifier: NSObjectProtocol] = [:]
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.julianamarques.BridgeProtocol", category: "bridge")

    public init(identity: Identity, store: PairingStore, hello: Hello) {
        self.identity = identity
        self.store = store
        self.hello = hello
    }

    public func start(port requested: UInt16? = preferredPort) {
        guard listener == nil else { return }
        let listener: NWListener
        do {
            let parameters = makeParameters()
            if let requested, let port = NWEndpoint.Port(rawValue: requested) {
                listener = try NWListener(using: parameters, on: port)
            } else {
                listener = try NWListener(using: parameters)
            }
        } catch {
            onEvent?(.failed(error.localizedDescription))
            return
        }
        listener.service = NWListener.Service(
            name: hello.name,
            type: Self.serviceType,
            txtRecord: NWTXTRecord(["v": String(protocolVersion), "id": Fingerprint.shortID(identity.fingerprint)])
        )
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state, requested: requested) }
        }
        self.listener = listener
        listener.start(queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: Self.keepAliveCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepAlive() }
        }
    }

    public func systemDidWake() {
        guard active != nil, wakeMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            MainActor.assumeIsolated { self?.networkReturnedAfterWake() }
        }
        wakeMonitor = monitor
        monitor.start(queue: .main)
    }

    private func networkReturnedAfterWake() {
        wakeMonitor?.cancel()
        wakeMonitor = nil
        guard let active else { return }
        log.info("Mac acordou; pedindo ao celular uma conexão nova")
        active.finish {}
    }

    public func stop(then completion: @escaping @MainActor () -> Void = {}) {
        wakeMonitor?.cancel()
        wakeMonitor = nil
        timer?.invalidate()
        timer = nil
        pairingTimer?.invalidate()
        pairingTimer = nil
        listener?.cancel()
        listener = nil
        port = nil
        let open = Array(connections.values)
        guard !open.isEmpty else { return completion() }
        var remaining = open.count
        for connection in open {
            connection.finish {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }

    private func listenerChanged(_ state: NWListener.State, requested: UInt16?) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue
            log.info("Escutando na porta \(self.port ?? 0, privacy: .public)")
            onEvent?(.ready)
        case .failed(let error):
            listener?.cancel()
            listener = nil
            timer?.invalidate()
            if requested != nil, case .posix(.EADDRINUSE) = error {
                log.info("Porta \(requested ?? 0, privacy: .public) ocupada; usando outra")
                start(port: nil)
            } else {
                log.error("Não foi possível escutar: \(error.localizedDescription, privacy: .public)")
                onEvent?(.failed(error.localizedDescription))
            }
        default:
            break
        }
    }

    private func makeParameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_local_identity(options, sec_identity_create(identity.secIdentity)!)
        sec_protocol_options_set_peer_authentication_required(options, true)
        let accepts: @Sendable (String) -> Bool = { [weak self] fingerprint in
            MainActor.assumeIsolated { self?.accepts(fingerprint) ?? false }
        }
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let trust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else { return complete(false) }
            complete(accepts(Fingerprint.of(SecCertificateCopyData(leaf) as Data)))
        }, .main)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return NWParameters(tls: tls, tcp: tcp)
    }

    private func accepts(_ fingerprint: String) -> Bool {
        if store.phone(withFingerprint: fingerprint) != nil { return true }
        if let pairing, !pairing.isExpired() { return true }
        log.info("Certificado desconhecido recusado: \(fingerprint, privacy: .public)")
        return false
    }

    @discardableResult
    public func beginPairing() -> PairingSession {
        let session = PairingSession()
        pairing = session
        pairingTimer?.invalidate()
        pairingTimer = Timer.scheduledTimer(withTimeInterval: max(session.expiresAt.timeIntervalSinceNow, 0), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.pairingEnded(expired: true) }
        }
        return session
    }

    public func cancelPairing() {
        pairingEnded(expired: false)
    }

    private func pairingEnded(expired: Bool) {
        pairingTimer?.invalidate()
        pairingTimer = nil
        guard pairing != nil else { return }
        pairing = nil
        if expired { onEvent?(.pairingExpired) }
    }

    public func forget(_ phone: PairedPhone) {
        store.remove(fingerprint: phone.fingerprint)
        for connection in connections.values where connection.fingerprint == phone.fingerprint {
            connection.send(Envelope(.unpair)) { connection.close() }
        }
    }

    private func accept(_ connection: NWConnection) {
        let bridge = BridgeConnection(connection)
        let key = ObjectIdentifier(bridge)
        connections[key] = bridge
        bridge.onMessage = { [weak self, weak bridge] envelope in
            guard let self, let bridge else { return }
            self.handle(envelope, from: bridge)
        }
        bridge.onClose = { [weak self, weak bridge] in
            guard let self, let bridge else { return }
            self.closed(bridge)
        }
        bridge.start()
        Timer.scheduledTimer(withTimeInterval: Self.setupTimeout, repeats: false) { [weak bridge] _ in
            MainActor.assumeIsolated {
                guard let bridge, bridge.phone == nil, !bridge.isTransfer else { return }
                bridge.close()
            }
        }
    }

    private func closed(_ connection: BridgeConnection) {
        connections[ObjectIdentifier(connection)] = nil
        if let activity = activities.removeValue(forKey: ObjectIdentifier(connection)) {
            ProcessInfo.processInfo.endActivity(activity)
        }
        if let transfer = incoming.removeValue(forKey: ObjectIdentifier(connection)), !transfer.isComplete {
            log.info("Transferência interrompida: \(transfer.file.name, privacy: .public)")
            transfer.discard()
            onEvent?(.transferEnded(transfer.file.id))
        }
        if let id = sending.removeValue(forKey: ObjectIdentifier(connection)) { failOffer(id) }
        guard connection === active else { return }
        active = nil
        log.info("Celular desconectado")
        onEvent?(.disconnected)
    }

    private func handle(_ envelope: Envelope, from connection: BridgeConnection) {
        switch envelope.message {
        case .hello(let hello):
            received(hello, from: connection)
        case .pairRequest(let request):
            received(request, from: connection)
        case .ping:
            connection.send(Envelope(.pong, replyTo: envelope.id))
        case .transferUpload(let file):
            receive(file, on: connection)
        case .transferDownload(let transfer):
            send(transfer.id, on: connection)
        case .transferChunk(let chunk):
            received(chunk, on: connection)
        case .transferResult(let result) where connection.isTransfer:
            sending[ObjectIdentifier(connection)] = nil
            if let transfer = offered.removeValue(forKey: result.id) {
                onEvent?(.fileSent(name: transfer.file.name, ok: result.ok))
                onEvent?(.transferEnded(result.id))
            }
            connection.close()
        case .status(let status) where connection === active:
            onEvent?(.status(status))
        case .callState(let call) where connection === active:
            onEvent?(.call(call))
        case .contactsResults(let results) where connection === active:
            onEvent?(.contacts(results, replyTo: envelope.replyTo))
        case .photo(let photo) where connection === active:
            onEvent?(.photo(photo))
        case .notificationPosted(let notification) where connection === active:
            onEvent?(.notificationPosted(notification))
        case .notificationRemoved(let notification) where connection === active:
            onEvent?(.notificationRemoved(notification.key))
        case .clipboard(let clipboard) where connection === active:
            onEvent?(.clipboard(clipboard.text))
        case .notificationActive(let notifications) where connection === active:
            onEvent?(.notificationsActive(notifications.keys))
        case .error(let error) where connection === active:
            onEvent?(.error(error, replyTo: envelope.replyTo))
        case .unpair where connection === active:
            if let phone = connection.phone {
                store.remove(fingerprint: phone.fingerprint)
                log.info("O celular esqueceu este Mac")
                onEvent?(.unpaired)
            }
            connection.close()
        default:
            break
        }
    }

    private func received(_ hello: Hello, from connection: BridgeConnection) {
        guard connection.hello == nil, let fingerprint = connection.fingerprint else { return }
        guard hello.version == protocolVersion else {
            let error = BridgeError(code: .version, message: "Atualize o Galaxy Bridge no Mac e no celular para a mesma versão.")
            connection.send(Envelope(.error(error))) { connection.close() }
            return
        }
        connection.hello = hello
        if var phone = store.phone(withFingerprint: fingerprint) {
            if phone.name != hello.name || phone.model != hello.model {
                phone.name = hello.name
                phone.model = hello.model
                store.save(phone)
            }
            activate(connection, as: phone)
        } else if pairing == nil || pairing?.isExpired() == true {
            reject(connection, .expired)
        }
    }

    private func received(_ request: PairRequest, from connection: BridgeConnection) {
        guard connection.phone == nil, let fingerprint = connection.fingerprint else { return }
        guard var session = pairing else { return reject(connection, .expired) }
        let result = session.check(request.secret)
        pairing = session
        switch result {
        case .accepted:
            pairingEnded(expired: false)
            let phone = PairedPhone(fingerprint: fingerprint, name: request.name, model: request.model)
            store.save(phone)
            log.info("Pareado com \(request.name, privacy: .public)")
            connection.send(Envelope(.pairAccepted(PairAccepted(name: hello.name))))
            onEvent?(.paired(phone))
            activate(connection, as: phone)
        case .invalid:
            reject(connection, .invalid)
        case .expired:
            reject(connection, .expired)
            pairingEnded(expired: true)
        }
    }

    private func reject(_ connection: BridgeConnection, _ reason: PairRejected.Reason) {
        connection.send(Envelope(.pairRejected(PairRejected(reason: reason)))) { connection.close() }
    }

    private func activate(_ connection: BridgeConnection, as phone: PairedPhone) {
        connection.phone = phone
        connection.send(Envelope(.hello(hello)))
        let previous = active
        active = connection
        if let previous, previous !== connection {
            previous.onClose = nil
            previous.close()
            connections[ObjectIdentifier(previous)] = nil
        }
        log.info("Conectado a \(phone.name, privacy: .public)")
        onEvent?(.connected(phone))
    }

    @discardableResult
    public func offer(_ url: URL) -> String? {
        guard let active, let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        nextID += 1
        let file = TransferFile(id: "f\(nextID)", name: url.lastPathComponent, size: Int64(size), mime: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType)
        offered[file.id] = OutgoingTransfer(file: file, url: url)
        active.send(Envelope(.transferOffer(file)))
        onEvent?(.transferProgress(TransferProgress(id: file.id, name: file.name, direction: .toPhone, done: 0, total: file.size)))
        Task { [weak self] in
            try? await Task.sleep(for: Self.offerTimeout)
            guard let self, !self.sending.values.contains(file.id) else { return }
            self.failOffer(file.id)
        }
        return file.id
    }

    private func failOffer(_ id: String) {
        guard let transfer = offered.removeValue(forKey: id) else { return }
        onEvent?(.fileSent(name: transfer.file.name, ok: false))
        onEvent?(.transferEnded(id))
    }

    private func startTransfer(on connection: BridgeConnection) -> Bool {
        guard connection.hello == nil, !connection.isTransfer,
              let fingerprint = connection.fingerprint, store.phone(withFingerprint: fingerprint) != nil
        else {
            connection.close()
            return false
        }
        connection.isTransfer = true
        activities[ObjectIdentifier(connection)] = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Transferindo um arquivo com o celular"
        )
        return true
    }

    private func receive(_ file: TransferFile, on connection: BridgeConnection) {
        guard startTransfer(on: connection) else { return }
        guard let transfer = IncomingTransfer(file) else {
            return connection.send(Envelope(.transferResult(TransferResult(id: file.id, ok: false, message: "Sem espaço no Mac")))) { connection.close() }
        }
        log.info("Recebendo \(file.name, privacy: .public) (\(file.size) bytes)")
        incoming[ObjectIdentifier(connection)] = transfer
        report(transfer)
        if transfer.isComplete { finish(transfer, on: connection) }
    }

    private func received(_ chunk: TransferChunk, on connection: BridgeConnection) {
        guard let transfer = incoming[ObjectIdentifier(connection)], chunk.id == transfer.file.id else { return connection.close() }
        do {
            try transfer.write(chunk.data)
        } catch {
            return connection.close()
        }
        report(transfer)
        if transfer.isComplete { finish(transfer, on: connection) }
    }

    private func finish(_ transfer: IncomingTransfer, on connection: BridgeConnection) {
        incoming[ObjectIdentifier(connection)] = nil
        connection.send(Envelope(.transferResult(TransferResult(id: transfer.file.id, ok: true))))
        onEvent?(.fileReceived(transfer.url, name: transfer.file.name))
        onEvent?(.transferEnded(transfer.file.id))
    }

    private func report(_ transfer: IncomingTransfer) {
        let file = transfer.file
        onEvent?(.transferProgress(TransferProgress(id: file.id, name: file.name, direction: .fromPhone, done: transfer.received, total: file.size)))
    }

    private func send(_ id: String, on connection: BridgeConnection) {
        guard startTransfer(on: connection) else { return }
        guard let transfer = offered[id] else { return connection.close() }
        log.info("Enviando \(transfer.file.name, privacy: .public)")
        sending[ObjectIdentifier(connection)] = id
        let file = transfer.file
        transfer.stream(on: connection) { [weak self] sent in
            self?.onEvent?(.transferProgress(TransferProgress(id: file.id, name: file.name, direction: .toPhone, done: sent, total: file.size)))
        }
    }

    @discardableResult
    public func send(_ message: Message) -> String? {
        guard let active else { return nil }
        nextID += 1
        let id = String(nextID)
        active.send(Envelope(message, id: id))
        return id
    }

    func keepAlive(now: Date = Date()) {
        guard let active else { return }
        if active.awaitingPong {
            guard now.timeIntervalSince(active.lastPing) > Self.pongTimeout else { return }
            log.info("Celular não respondeu ao ping em \(Int(Self.pongTimeout), privacy: .public) s")
            active.close()
        } else if now.timeIntervalSince(active.lastPing) >= Self.pingInterval {
            active.ping(at: now)
        }
    }
}
