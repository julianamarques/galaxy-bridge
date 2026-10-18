import AppKit
import BridgeProtocol
import GalaxyKit
import SystemConfiguration

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
    @Published private(set) var appPhone: PairedPhone?
    @Published private(set) var isAppConnected = false {
        didSet { if !isAppConnected { battery = nil } }
    }
    @Published private(set) var connection: Connection = .idle {
        didSet {
            guard connection.serial != oldValue.serial else { return }
            refreshPhoneStatus()
        }
    }
    @Published private(set) var battery: Battery?
    @Published private(set) var phoneCountry: String?
    @Published private(set) var callError: String?
    @Published var setupRequested = false

    lazy var setup = SetupModel(app: self)

    private(set) var bridge: BridgeServer?
    private let deviceMonitor = DeviceMonitor()
    private var trackedDevices: [ADBDevice] = []
    private var isMonitoringDevices = false
    private var keepAliveTask: Task<Void, Never>?
    private var quitCompletion: (@MainActor () -> Void)?
    private var statusTask: Task<Void, Never>?
    private static let deviceKey = "pairedDevice"
    private static let reconnectInterval: Duration = .seconds(30)
    private static let statusInterval: Duration = .seconds(60)
    private static let quitTimeout: Duration = .seconds(1)

    init() {
        pairedDevice = UserDefaults.standard.data(forKey: Self.deviceKey)
            .flatMap { try? JSONDecoder().decode(PairedDevice.self, from: $0) }
    }

    var deviceName: String { appPhone?.name ?? pairedDevice?.name ?? "Galaxy" }

    var isConfigured: Bool { appPhone != nil || pairedDevice != nil }

    var isConnected: Bool { appPhone != nil ? isAppConnected : connection.serial != nil }

    func launched() {
        _ = PhoneNumbers.shared
        let store = PairingStore(file: Self.pairingStoreFile)
        appPhone = store.phones.last
        if appPhone != nil {
            startBridge(store: store)
            return
        }
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

    func terminate(then completion: @escaping @MainActor () -> Void) {
        deviceMonitor.stop()
        keepAliveTask?.cancel()
        statusTask?.cancel()
        guard let bridge else { return completion() }
        quitCompletion = completion
        bridge.stop { [weak self] in self?.finishQuitting() }
        Task { [weak self] in
            try? await Task.sleep(for: Self.quitTimeout)
            self?.finishQuitting()
        }
    }

    func systemDidWake() {
        bridge?.systemDidWake()
    }

    private func finishQuitting() {
        let completion = quitCompletion
        quitCompletion = nil
        completion?()
    }

    private func startMonitoring() {
        guard !isMonitoringDevices else { return }
        isMonitoringDevices = true
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

    func didPair(_ device: PairedDevice, serial: String) {
        var device = device
        if device.usbSerial == nil, let usbSerial = pairedDevice?.usbSerial, device.matchesUSB(usbSerial) {
            device.usbSerial = usbSerial
        }
        save(device)
        connection = .connected(serial: serial)
        startMonitoring()
        startKeepAlive()
    }

    func setUpWiFi() {
        setup.beginPairing()
        setupRequested = true
    }

    func setUpApp() {
        setup.beginAppPairing()
        setupRequested = true
    }

    func forget() {
        if let phone = appPhone {
            bridge?.forget(phone)
            clearAppPhone()
        } else {
            if let serial = connection.serial, !ADBOutputParser.isUSBSerial(serial) {
                Task { await ADB.disconnect(serial) }
            }
            dropADBDevice()
        }
        setup.reset()
        setupRequested = true
    }

    private func dropADBDevice() {
        keepAliveTask?.cancel()
        UserDefaults.standard.removeObject(forKey: Self.deviceKey)
        pairedDevice = nil
        connection = .idle
    }

    private func save(_ device: PairedDevice) {
        pairedDevice = device
        if let data = try? JSONEncoder().encode(device) {
            UserDefaults.standard.set(data, forKey: Self.deviceKey)
        }
    }

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

    var dialCountry: String? {
        phoneCountry ?? Locale.current.region?.identifier.lowercased()
    }

    func call(_ number: PhoneNumber) {
        callError = nil
        Task { callError = await placeCall(number) }
    }

    var canEndCall: Bool { appPhone == nil && connection.serial != nil }

    func endCall() {
        guard canEndCall, let serial = connection.serial else { return }
        Task { await ADB.endCall(serial: serial) }
    }

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

    private func placeCall(_ number: PhoneNumber) async -> String? {
        if appPhone != nil {
            let dialable = PhoneNumbers.shared.dialable(number, country: dialCountry)
            guard bridge?.send(.callPlace(CallPlace(number: dialable.digits))) != nil else {
                return String(localized: "O \(deviceName) não está conectado. Confira se ele está na mesma rede Wi-Fi que este Mac e se o app Galaxy Bridge está instalado nele.")
            }
            Log.phone.info("Ligação pedida ao app do Galaxy")
            return nil
        }
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

extension AppModel {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.appName, isDirectory: true)
    }

    static var pairingStoreFile: URL { supportDirectory.appendingPathComponent("paired-phones.json") }

    @discardableResult
    func startBridge(store: PairingStore? = nil) -> BridgeServer? {
        if let bridge { return bridge }
        do {
            let identity = try Identity.loadOrCreate(in: Self.supportDirectory.appendingPathComponent("identity", isDirectory: true))
            let store = store ?? PairingStore(file: Self.pairingStoreFile)
            let hello = Hello(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                name: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac",
                model: Self.hardwareModel
            )
            let bridge = BridgeServer(identity: identity, store: store, hello: hello)
            bridge.onEvent = { [weak self] in self?.handle($0) }
            bridge.start()
            self.bridge = bridge
            return bridge
        } catch {
            Log.connection.error("Não foi possível criar a identidade do Mac: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func handle(_ event: BridgeServer.Event) {
        switch event {
        case .ready:
            setup.bridgeChanged()
        case .failed(let message):
            Log.connection.error("Servidor do Galaxy Bridge parou: \(message, privacy: .public)")
            setup.bridgeChanged(failure: message)
        case .connected(let phone):
            appPhone = phone
            isAppConnected = true
            callError = nil
        case .disconnected:
            isAppConnected = false
        case .paired(let phone):
            didPairApp(phone)
        case .pairingExpired:
            setup.pairingExpired()
        case .unpaired:
            clearAppPhone()
        case .status(let status):
            let battery = Battery(level: status.battery.level, isCharging: status.battery.charging)
            if battery != self.battery { self.battery = battery }
            if let country = (status.networkCountry ?? status.simCountry)?.lowercased(), country != phoneCountry {
                phoneCountry = country
            }
        case .error(let error):
            callError = error.message
        }
    }

    private func didPairApp(_ phone: PairedPhone) {
        deviceMonitor.stop()
        isMonitoringDevices = false
        dropADBDevice()
        appPhone = phone
        setup.appPaired()
    }

    private func clearAppPhone() {
        appPhone = nil
        isAppConnected = false
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
