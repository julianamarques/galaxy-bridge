import AppKit
import BridgeProtocol
import GalaxyKit

@MainActor
final class MirrorController: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running
        case reconnecting
    }

    @Published private(set) var state = State.idle
    @Published private(set) var error: String?
    @Published var hint: String?

    var findDevice: (() async -> String?)?
    var makeAppTransport: (() -> AppTransport?)?
    private(set) var appTransport: AppTransport?
    var deviceName: () -> String = { "Galaxy" }

    private static let maxStartRetries = 2
    private static let reconnectWindow: TimeInterval = 30
    private static let firstFrameTimeout: TimeInterval = 12
    private static let consentTimeout: TimeInterval = 120
    static let consentHint = String(localized: "Toque na notificação do Galaxy e confirme para começar.")

    private var task: Task<Void, Never>?
    private var session: MirrorSession?
    private var window: MirrorWindowController?

    var isActive: Bool { state != .idle }

    func toggle() {
        isActive ? stop() : start()
    }

    func showWindow() {
        NSApp.activate()
        window?.window?.makeKeyAndOrderFront(nil)
    }

    func start() {
        Log.connection.info("Espelhamento pedido (estado: \(String(describing: self.state), privacy: .public))")
        guard task == nil else { return showWindow() }
        error = nil
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        session?.stop()
    }

    private func run() async {
        state = .starting
        defer {
            tearDownSession()
            window?.closeWithoutNotifying()
            window = nil
            NSApp.setActivationPolicy(.accessory)
            hint = nil
            state = .idle
            task = nil
        }

        if let transport = makeAppTransport?() {
            do {
                _ = try await runAppSession(transport)
            } catch is CancellationError {
            } catch {
                Log.connection.error("Espelhamento pelo app falhou: \(error.localizedDescription, privacy: .public)")
                self.error = error.localizedDescription
            }
            return
        }

        var attempt = 0
        var reconnectDeadline: Date?
        while !Task.isCancelled {
            do {
                if attempt > 0 { try await Task.sleep(for: .seconds(min(attempt, 4))) }
                let serial = await findDevice?()
                Log.connection.info("Espelhamento: aparelho \(serial ?? "não encontrado", privacy: .public)")
                guard let serial else {
                    if let reconnectDeadline, Date() < reconnectDeadline {
                        attempt += 1
                        continue
                    }
                    error = String(localized: "Conecte o Galaxy pelo cabo USB ou ative a Depuração sem fio para espelhar a tela.")
                    return
                }
                try Task.checkCancellation()
                guard let message = try await runSession(serial: serial) else { return }
                Log.connection.error("Espelhamento caiu: \(message, privacy: .public)")
                tearDownSession()
                reconnectDeadline = Date().addingTimeInterval(Self.reconnectWindow)
                attempt = 1
                state = .reconnecting
                window?.showReconnecting()
            } catch is CancellationError {
                return
            } catch {
                Log.connection.error("Espelhamento falhou: \(error.localizedDescription, privacy: .public)")
                tearDownSession()
                attempt += 1
                if let reconnectDeadline {
                    if Date() < reconnectDeadline { continue }
                    return
                }
                guard attempt > Self.maxStartRetries else { continue }
                self.error = error.localizedDescription
                return
            }
        }
    }

    private func runSession(serial: String) async throws -> String? {
        let options = MirrorOptions()
        let connection = try await ScrcpyServer.start(serial: serial, options: options)
        let session = MirrorSession(transport: ScrcpyTransport(connection: connection, codec: options.codec))
        try await run(session, options: options, timeout: Self.firstFrameTimeout)
        if options.turnScreenOff {
            session.send(.setDisplayPower(on: false))
        }
        return await session.waitUntilEnded()
    }

    private func runAppSession(_ transport: AppTransport) async throws -> String? {
        let options = MirrorOptions()
        appTransport = transport
        defer { appTransport = nil }
        let session = MirrorSession(transport: transport)
        hint = Self.consentHint
        try await run(session, options: options, timeout: Self.consentTimeout) {
            transport.begin(MirrorStart(maxSize: options.quality.maxSize, bitRate: options.quality.bitRate))
        }
        return await session.waitUntilEnded()
    }

    private func run(_ session: MirrorSession, options: MirrorOptions, timeout: TimeInterval, begin: () -> Void = {}) async throws {
        self.session = session
        let window = window ?? makeWindow(options: options)
        window.attach(session)
        session.start()
        begin()

        try await session.waitForFirstFrame(timeout: timeout)
        error = nil
        if hint == Self.consentHint { hint = nil }
        state = .running
        window.sessionDidStart()
        showWindow()
    }

    private func makeWindow(options: MirrorOptions) -> MirrorWindowController {
        let window = MirrorWindowController(title: deviceName(), alwaysOnTop: options.alwaysOnTop)
        window.onClose = { [weak self] in self?.stop() }
        self.window = window
        NSApp.setActivationPolicy(.regular)
        return window
    }

    private func tearDownSession() {
        session?.stop()
        session = nil
    }
}
