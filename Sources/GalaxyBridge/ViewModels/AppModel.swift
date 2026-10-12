import AppKit
import GalaxyKit

@MainActor
final class AppModel: ObservableObject {
    enum Connection: Equatable {
        case idle
        case connecting
        case connected(serial: String)
        case failed(ConnectionProblem)

        var serial: String? {
            if case .connected(let serial) = self { return serial }
            return nil
        }
    }

    @Published private(set) var pairedDevice: PairedDevice?
    @Published private(set) var connection: Connection = .idle {
        didSet {
            guard connection.serial != oldValue.serial else { return }
            refreshPhoneStatus()
        }
    }
    @Published private(set) var battery: Battery?
    /// País em que o Galaxy está, que define a máscara do discador e o formato dos números.
    @Published private(set) var phoneCountry: String?
    @Published private(set) var callError: String?
    /// Pedido para abrir a janela de configuração; atendido pela `MenuBarLabel`, que tem acesso ao `openWindow`.
    @Published var setupRequested = false

    lazy var setup = SetupModel(app: self)

    private let deviceMonitor = DeviceMonitor()
    private var trackedDevices: [ADBDevice] = []
    private var keepAliveTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private static let deviceKey = "pairedDevice"
    private static let reconnectInterval: Duration = .seconds(30)
    private static let statusInterval: Duration = .seconds(60)

    init() {
        pairedDevice = UserDefaults.standard.data(forKey: Self.deviceKey)
            .flatMap { try? JSONDecoder().decode(PairedDevice.self, from: $0) }
    }

    var deviceName: String { pairedDevice?.name ?? "Galaxy" }

    func launched() {
        // Carrega os dados de números de telefone agora, para a primeira tecla no discador não travar o menu.
        _ = PhoneNumbers.shared
        Task {
            await ADB.startServer()
            startMonitoring()
            if pairedDevice == nil {
                setupRequested = true
            } else {
                startKeepAlive()
            }
        }
    }

    func terminate() {
        deviceMonitor.stop()
        keepAliveTask?.cancel()
        statusTask?.cancel()
    }

    // MARK: Conexão

    private func startMonitoring() {
        deviceMonitor.start { [weak self] devices in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.devicesChanged(devices) }
            }
        }
    }

    private func devicesChanged(_ devices: [ADBDevice]) {
        trackedDevices = devices
        refreshConnection()
    }

    private func refreshConnection() {
        guard let device = pairedDevice, connection != .connecting else { return }
        let available = trackedDevices.filter { $0.isReady && device.matches($0.serial) }
        if let preferred = available.first(where: \.isUSB) ?? available.first {
            if connection.serial != preferred.serial { connection = .connected(serial: preferred.serial) }
        } else if case .connected = connection {
            connection = .idle
        }
    }

    /// Mantém o Galaxy conectado enquanto o app está aberto: tenta reconectar sempre que a conexão cai.
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.connection.serial == nil, self.connection != .connecting {
                    await self.ensureConnected()
                }
                try? await Task.sleep(for: Self.reconnectInterval)
            }
        }
    }

    func reconnect() {
        Task { await ensureConnected() }
    }

    @discardableResult
    func ensureConnected() async -> String? {
        guard let device = pairedDevice else { return nil }

        if let usb = await ADB.usbDevices().first(where: { $0.isReady && device.matchesUSB($0.serial) }) {
            return await connected(to: usb.serial)
        }
        if let serial = connection.serial, await ADB.isReady(serial) {
            return serial
        }
        connection = .connecting
        Log.connection.info("Procurando o Galaxy (cabo\(device.supportsWiFi ? " e Wi-Fi" : "", privacy: .public))")

        do {
            let serial = try await ADB.waitForConnection(
                guid: device.guid,
                lastAddress: device.lastAddress,
                acceptsUSB: device.matchesUSB,
                timeout: device.supportsWiFi ? 20 : 10
            )
            return await connected(to: serial)
        } catch {
            let problem = device.supportsWiFi ? error : ToolError.usbNotConnected
            Log.connection.error("Galaxy não encontrado: \(problem.localizedDescription, privacy: .public)")
            connection = .failed(ConnectionProblem(problem))
            return nil
        }
    }

    private func connected(to serial: String) async -> String {
        guard var device = pairedDevice else { return serial }
        if ADBOutputParser.isUSBSerial(serial) {
            if device.usbSerial != serial { device.usbSerial = serial }
            if device.guid != nil { await ADB.enableWirelessDebugging(serial: serial) }
        } else if let address = ADBOutputParser.networkAddress(serial) {
            device.lastAddress = address
        }
        save(device)
        Log.connection.info("Conectado ao Galaxy por \(ADBOutputParser.isUSBSerial(serial) ? "cabo" : "Wi-Fi", privacy: .public): \(serial, privacy: .public)")
        connection = .connected(serial: serial)
        return serial
    }

    // MARK: Configuração

    func didPair(_ device: PairedDevice, serial: String) {
        var device = device
        if device.usbSerial == nil, let usbSerial = pairedDevice?.usbSerial, device.matchesUSB(usbSerial) {
            device.usbSerial = usbSerial
        }
        save(device)
        connection = .connected(serial: serial)
        startKeepAlive()
    }

    func setUpWiFi() {
        setup.beginPairing()
        setupRequested = true
    }

    func forget() {
        keepAliveTask?.cancel()
        if let serial = connection.serial, !ADBOutputParser.isUSBSerial(serial) {
            Task { await ADB.disconnect(serial) }
        }
        UserDefaults.standard.removeObject(forKey: Self.deviceKey)
        pairedDevice = nil
        connection = .idle
        setup.reset()
        setupRequested = true
    }

    private func save(_ device: PairedDevice) {
        pairedDevice = device
        if let data = try? JSONEncoder().encode(device) {
            UserDefaults.standard.set(data, forKey: Self.deviceKey)
        }
    }

    // MARK: Bateria e país

    /// Lê a bateria e o país em que o Galaxy está (que muda em viagens) a cada minuto enquanto ele está conectado.
    private func refreshPhoneStatus() {
        statusTask?.cancel()
        guard let serial = connection.serial else {
            battery = nil
            return
        }
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                let battery = await ADB.battery(serial: serial)
                let country = await ADB.phoneCountry(serial: serial)
                guard !Task.isCancelled, let self else { return }
                if battery != self.battery { self.battery = battery }
                if let country, country != self.phoneCountry { self.phoneCountry = country }
                try? await Task.sleep(for: Self.statusInterval)
            }
        }
    }

    // MARK: Ligações

    /// O país usado na máscara e na discagem: onde o Galaxy está e, antes de ele conectar, a região do Mac.
    var dialCountry: String? {
        phoneCountry ?? Locale.current.region?.identifier.lowercased()
    }

    func call(_ number: PhoneNumber) {
        callError = nil
        Task { callError = await placeCall(number) }
    }

    func endCall() {
        guard let serial = connection.serial else { return }
        Task { await ADB.endCall(serial: serial) }
    }

    /// Links `tel:` abertos em outros apps (Safari, Contatos, Calendário…).
    func open(_ urls: [URL]) {
        guard let number = urls.lazy.compactMap(PhoneNumber.init(url:)).first else { return }
        Task {
            guard let error = await placeCall(number) else { return }
            let alert = NSAlert()
            alert.messageText = String(localized: "Não foi possível ligar pelo Galaxy")
            alert.informativeText = error
            NSApp.activate()
            alert.runModal()
        }
    }

    /// Devolve a mensagem de erro, ou `nil` se a ligação começou.
    private func placeCall(_ number: PhoneNumber) async -> String? {
        guard pairedDevice != nil else {
            setupRequested = true
            return String(localized: "Nenhum Galaxy está configurado neste Mac. Configure-o e tente ligar de novo.")
        }
        guard let serial = await ensureConnected() else {
            return String(localized: "O \(deviceName) não está conectado. Confira se ele está na mesma rede Wi-Fi que este Mac ou conecte o cabo USB.")
        }
        let country = await ADB.phoneCountry(serial: serial) ?? dialCountry
        do {
            try await ADB.call(PhoneNumbers.shared.dialable(number, country: country), serial: serial)
            Log.phone.info("Ligação iniciada no Galaxy")
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
