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
    @Published private(set) var call: CallState?
    @Published private(set) var callAnsweredAt: Date?
    @Published private(set) var contactSuggestions: [ContactSuggestion] = []
    @Published private(set) var contactsError: String?
    @Published private(set) var photos: [String: NSImage] = [:]
    @Published var setupRequested = false

    lazy var setup = SetupModel(app: self)

    private(set) var bridge: BridgeServer?
    private let callNotifier = CallNotifier()
    private var declinedCall: String?
    private var searchRequest: String?
    private var searchTask: Task<Void, Never>?
    private var requestedPhotos: Set<String> = []
    private static let searchDelay: Duration = .milliseconds(150)
    private static let searchLimit = 8
    private static let maxSuggestions = 6
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

    var canEndCall: Bool { appPhone == nil ? connection.serial != nil : call != nil }

    func endCall() {
        if let call {
            Log.phone.info("Encerrando a ligação pelo Mac")
            #if DEBUG
            if call.call.hasPrefix(Self.previewCall) { return callChanged(CallState(call: call.call, state: .ended, direction: call.direction)) }
            #endif
            bridge?.send(.callEnd(CallID(call: call.call)))
            return
        }
        guard canEndCall, let serial = connection.serial else { return }
        Task { await ADB.endCall(serial: serial) }
    }

    func answerCall() {
        guard let id = call?.call else { return }
        Log.phone.info("Atendendo a ligação pelo Mac")
        #if DEBUG
        if id.hasPrefix(Self.previewCall) { return callChanged(CallState(call: id, state: .active, direction: .incoming, number: call?.number, name: call?.name)) }
        #endif
        bridge?.send(.callAnswer(CallID(call: id)))
    }

    func declineCall() {
        guard let id = call?.call else { return }
        declinedCall = id
        Log.phone.info("Recusando a ligação pelo Mac")
        #if DEBUG
        if id.hasPrefix(Self.previewCall) { return callChanged(CallState(call: id, state: .ended, direction: .incoming, number: call?.number, name: call?.name)) }
        #endif
        bridge?.send(.callDecline(CallID(call: id)))
    }

    var callerName: String {
        guard let call else { return "" }
        return call.name ?? callerNumber ?? String(localized: "Número desconhecido")
    }

    var callerNumber: String? {
        call?.number.map { PhoneNumbers.shared.display($0, country: dialCountry) }
    }

    func searchContacts(_ query: String) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespaces)
        guard isAppConnected, query.count >= 2 else {
            searchRequest = nil
            contactSuggestions = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled, let self else { return }
            searchRequest = bridge?.send(.contactsSearch(ContactsSearch(query: query, limit: Self.searchLimit)))
        }
    }

    func requestPhoto(_ contact: String) {
        guard photos[contact] == nil, requestedPhotos.insert(contact).inserted else { return }
        bridge?.send(.photoRequest(PhotoRequest(contact: contact)))
    }

    private func callChanged(_ state: CallState) {
        if let contact = state.contact { requestPhoto(contact) }
        let previous = call?.call == state.call ? call : nil
        let wasAnswered = previous != nil && callAnsweredAt != nil
        switch state.state {
        case .ringing:
            call = state
            callAnsweredAt = nil
        case .active:
            call = state
            if !wasAnswered { callAnsweredAt = Date() }
        case .voicemail:
            call = state
            callAnsweredAt = nil
        case .ended:
            let caller = callerName.isEmpty ? (state.name ?? state.number ?? "") : callerName
            if state.direction == .incoming, !wasAnswered, declinedCall != state.call {
                callNotifier.missed(call: state.call, caller: caller, toVoicemail: previous?.state == .voicemail)
            }
            call = nil
            callAnsweredAt = nil
            declinedCall = nil
        }
    }

    #if DEBUG
    private static let previewCall = "preview"

    func previewIncomingCall() {
        Task {
            for round in 1...2 {
                let id = "\(Self.previewCall)-\(round)"
                callChanged(CallState(call: id, state: .ringing, direction: .incoming))
                try? await Task.sleep(for: .milliseconds(500))
                callChanged(CallState(call: id, state: .ringing, direction: .incoming, number: "086999990001", name: "Maria"))
                try? await Task.sleep(for: .seconds(15))
                if call?.call == id, call?.state == .ringing {
                    callChanged(CallState(call: id, state: .ended, direction: .incoming, number: "086999990001", name: "Maria"))
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    #endif

    private func dropCall() {
        call = nil
        callAnsweredAt = nil
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
            callNotifier.requestAuthorization()
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
            dropCall()
            requestedPhotos.removeAll()
            photos.removeAll()
            contactSuggestions = []
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
        case .call(let state):
            callChanged(state)
        case .contacts(let results, let replyTo):
            guard replyTo != nil, replyTo == searchRequest else { return }
            contactsError = nil
            contactSuggestions = Array(results.contacts.lazy.flatMap { contact in
                contact.numbers.map { ContactSuggestion(contact: contact, number: $0, country: self.dialCountry) }
            }.prefix(Self.maxSuggestions))
            for contact in results.contacts where contact.hasPhoto { requestPhoto(contact.id) }
        case .photo(let photo):
            if let image = NSImage(data: photo.data) { photos[photo.contact] = image }
        case .error(let error, let replyTo):
            if replyTo != nil, replyTo == searchRequest {
                contactsError = error.message
            } else {
                callError = error.message
            }
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

struct ContactSuggestion: Identifiable {
    let contact: Contact
    let number: Contact.Number
    let detail: String

    var id: String { contact.id + "|" + number.number }

    @MainActor
    init(contact: Contact, number: Contact.Number, country: String?) {
        self.contact = contact
        self.number = number
        let formatted = PhoneNumbers.shared.display(number.number, country: country)
        detail = [number.label, formatted].compactMap { $0 }.joined(separator: " · ")
    }
}
