import BridgeProtocol
import Foundation
import GalaxyKit

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Equatable {
        case welcome
        case appPair
        case missingTools
        case found(serial: String, name: String)
        case prepare
        case pair
        case usb
        case connecting
        case failed(ConnectionProblem)
        case done
    }

    enum PairingMode { case qr, code }

    enum USBStatus { case waiting, unauthorized }

    private struct PendingConnection {
        let guid: String?
        let host: String
    }

    @Published var step: Step = .welcome
    @Published var mode: PairingMode = .qr
    @Published private(set) var discovered: [MDNSService] = []
    @Published var selectedAddress: String?
    @Published var manualAddress = ""
    @Published var code = "" {
        didSet {
            let digits = String(code.filter(\.isNumber).prefix(6))
            if digits != code { code = digits }
        }
    }
    @Published private(set) var isPairing = false
    @Published private(set) var codeError: String?
    @Published private(set) var usbStatus: USBStatus = .waiting
    @Published private(set) var isLocalNetworkDenied = false

    @Published private(set) var appLink: String?
    @Published private(set) var appCode = ""
    @Published private(set) var macFingerprint = ""
    @Published private(set) var appPairingProblem: String?
    private var appToken: String?

    private(set) var qrName = ""
    private(set) var qrPassword = ""
    private(set) var qrPayload = ""

    private unowned let app: AppModel
    private var task: Task<Void, Never>?
    private var pending: PendingConnection?

    init(app: AppModel) {
        self.app = app
        makeCredentials()
    }

    func continueFromWelcome() {
        guard Tools.isInstalled else {
            step = .missingTools
            return
        }
        task?.cancel()
        task = Task {
            await ADB.startServer()
            guard let ready = await ADB.devices().first(where: \.isReady) else {
                step = .prepare
                return
            }
            let name = await ADB.deviceName(ready.serial)
            guard !Task.isCancelled else { return }
            step = .found(serial: ready.serial, name: name)
        }
    }

    func useFound(serial: String) {
        task?.cancel()
        task = Task {
            await finish(serial: serial, guid: ADBOutputParser.mdnsGUID(serial), usbSerial: ADBOutputParser.isUSBSerial(serial) ? serial : nil)
        }
    }

    func beginPairing() {
        step = .pair
        codeError = nil
        startPolling()
    }

    func beginUSB() {
        step = .usb
        usbStatus = .waiting
        startUSBPolling()
    }

    func retry() {
        guard Tools.isInstalled else {
            step = .missingTools
            return
        }
        if pending != nil {
            task?.cancel()
            task = Task { await connectPending() }
        } else {
            beginPairing()
        }
    }

    func windowClosed() {
        stopAppPairing()
        stopTask()
        if step != .done || !app.isConfigured { step = .welcome }
    }

    func reset() {
        stopAppPairing()
        stopTask()
        step = .welcome
        mode = .qr
        discovered = []
        selectedAddress = nil
        manualAddress = ""
        code = ""
        codeError = nil
        pending = nil
        makeCredentials()
    }

    private func makeCredentials() {
        qrName = "studio-" + String.random(8)
        qrPassword = String.random(12)
        qrPayload = "WIFI:T:ADB;S:\(qrName);P:\(qrPassword);;"
    }

    private func startPolling() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.step == .pair else { return }
                let services: [MDNSService]
                do {
                    services = try await Bonjour.services(ofType: MDNSService.pairingType)
                    if self.isLocalNetworkDenied { self.isLocalNetworkDenied = false }
                } catch {
                    if !self.isLocalNetworkDenied { self.isLocalNetworkDenied = true }
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                let discovered = services.filter { $0.name != self.qrName }
                if discovered != self.discovered { self.discovered = discovered }
                if !discovered.contains(where: { $0.address == self.selectedAddress }) {
                    self.selectedAddress = discovered.first?.address
                }
                if !self.isPairing, let qr = services.first(where: { $0.name == self.qrName }) {
                    await self.pair(address: qr.address, code: self.qrPassword)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startUSBPolling() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.step == .usb else { return }
                let devices = await ADB.usbDevices()
                if let ready = devices.first(where: \.isReady) {
                    await self.finish(serial: ready.serial, guid: self.pending?.guid, usbSerial: ready.serial)
                    return
                }
                let status: USBStatus = devices.contains { $0.state == "unauthorized" } ? .unauthorized : .waiting
                if status != self.usbStatus { self.usbStatus = status }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTask() {
        task?.cancel()
        task = nil
    }

    var canSubmitCode: Bool {
        code.count == 6 && pairingAddress != nil && !isPairing
    }

    private var pairingAddress: String? {
        let manual = manualAddress.trimmingCharacters(in: .whitespaces)
        if !manual.isEmpty { return manual }
        return selectedAddress
    }

    func submitCode() {
        guard canSubmitCode, let address = pairingAddress else { return }
        task?.cancel()
        task = Task { await pair(address: address, code: code) }
    }

    private func pair(address: String, code: String) async {
        isPairing = true
        codeError = nil
        defer { isPairing = false }

        do {
            let guid = try await ADB.pair(address: address, code: code)
            pending = PendingConnection(guid: guid, host: ADBOutputParser.host(of: address))
        } catch {
            guard !Task.isCancelled else { return }
            if mode == .code {
                codeError = error.localizedDescription
                startPolling()
            } else {
                step = .failed(ConnectionProblem(error))
            }
            return
        }

        await connectPending()
    }

    private func connectPending() async {
        guard let pending else { return }
        step = .connecting
        do {
            let serial = try await ADB.waitForConnection(guid: pending.guid, host: pending.host)
            await finish(serial: serial, guid: pending.guid, usbSerial: nil)
        } catch {
            guard !Task.isCancelled else { return }
            step = .failed(ConnectionProblem(error))
        }
    }

    private func finish(serial: String, guid: String?, usbSerial: String?) async {
        let name = await ADB.deviceName(serial)
        let device = PairedDevice(
            guid: guid,
            name: name,
            lastAddress: ADBOutputParser.networkAddress(serial),
            usbSerial: usbSerial
        )
        app.didPair(device, serial: serial)
        pending = nil
        step = .done
    }
}

extension SetupModel {
    func beginAppPairing() {
        stopTask()
        step = .appPair
        guard let bridge = app.startBridge() else {
            appLink = nil
            appPairingProblem = String(localized: "Não foi possível preparar a conexão segura deste Mac.")
            return
        }
        let session = bridge.beginPairing()
        appToken = session.token
        appCode = "\(session.code.prefix(3)) \(session.code.suffix(3))"
        macFingerprint = Fingerprint.display(bridge.identity.fingerprint)
        updateAppLink()
    }

    func bridgeChanged(failure: String? = nil) {
        guard step == .appPair else { return }
        if let failure {
            appLink = nil
            appPairingProblem = failure
        } else {
            updateAppLink()
        }
    }

    func pairingExpired() {
        if step == .appPair { beginAppPairing() }
    }

    func appPaired() {
        stopAppPairing()
        step = .done
    }

    func useAndroidDebugging() {
        stopAppPairing()
        continueFromWelcome()
    }

    private func updateAppLink() {
        guard let bridge = app.bridge, let token = appToken, let port = bridge.port else {
            appLink = nil
            return
        }
        guard let host = LocalNetwork.interfaces().first?.address else {
            appLink = nil
            appPairingProblem = String(localized: "Conecte este Mac a uma rede Wi-Fi.")
            return
        }
        appPairingProblem = nil
        appLink = PairingLink(host: host, port: port, fingerprint: bridge.identity.fingerprint, token: token).url.absoluteString
    }

    private func stopAppPairing() {
        appToken = nil
        app.bridge?.cancelPairing()
    }
}
