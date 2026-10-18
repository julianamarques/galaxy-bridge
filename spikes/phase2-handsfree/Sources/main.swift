import AppKit
import CoreAudio
import IOBluetooth
import SwiftUI

final class Spike: NSObject, ObservableObject, IOBluetoothHandsFreeDeviceDelegate {
    @Published var lines: [String] = []
    @Published var devices: [IOBluetoothDevice] = []
    @Published var selected: String = ""
    private var handsFree: IOBluetoothHandsFreeDevice?
    private let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/GalaxyBridgeHandsFreeSpike.log")
    private let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    func refreshDevices() {
        var seen = Set<String>()
        devices = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []).filter { seen.insert($0.addressString ?? "").inserted }
        log("Pareados: " + devices.map { "\($0.name ?? "?") [\($0.addressString ?? "?")] conectado=\($0.isConnected()) classe=\($0.deviceClassMajor)" }.joined(separator: "; "))
        if let phone = devices.first(where: { $0.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone) }) {
            selected = phone.addressString ?? ""
        }
    }

    func connect() {
        guard let device = devices.first(where: { $0.addressString == selected }) else { return log("Escolha um aparelho") }
        log("Viva-voz de \(device.name ?? "?"): serviço de viva-voz do celular = \(device.handsFreeAudioGatewayServiceRecord() != nil)")
        let handsFree = IOBluetoothHandsFreeDevice(device: device, delegate: self)
        handsFree?.supportedFeatures = IOBluetoothHandsFreeDeviceFeatures.cliPresentation.rawValue
            | IOBluetoothHandsFreeDeviceFeatures.enhancedCallStatus.rawValue
            | IOBluetoothHandsFreeDeviceFeatures.remoteVolumeControl.rawValue
            | IOBluetoothHandsFreeDeviceFeatures.ecAndOrNRFunction.rawValue
            | IOBluetoothHandsFreeDeviceFeatures.codecNegotiation.rawValue
        self.handsFree = handsFree
        log("Conectando como viva-voz…")
        handsFree?.connect()
    }

    func disconnect() { handsFree?.disconnect(); log("Desconectar pedido") }
    func audioToMac() { handsFree?.transferAudioToComputer(); log("Áudio para o Mac pedido") }
    func audioToPhone() { handsFree?.transferAudioToPhone(); log("Áudio para o celular pedido") }
    func openSCO() { handsFree?.connectSCO(); log("Abrir SCO pedido") }
    func answer() { handsFree?.acceptCall(); log("Atender pedido") }
    func hangUp() { handsFree?.endCall(); log("Desligar pedido") }
    func callList() { handsFree?.currentCallList(); log("Lista de ligações pedida") }

    func listAudioDevices() {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        let names = ids.map { id -> String in
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            _ = withUnsafeMutablePointer(to: &name) { AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, $0) }
            var rate = Float64(0)
            var rateSize = UInt32(MemoryLayout<Float64>.size)
            var rateAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(id, &rateAddress, 0, nil, &rateSize, &rate)
            return "\(name) (\(Int(rate)) Hz, entrada=\(channels(id, kAudioDevicePropertyScopeInput)), saída=\(channels(id, kAudioDevicePropertyScopeOutput)))"
        }
        log("Dispositivos de áudio: " + names.joined(separator: "; "))
    }

    private func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    func log(_ text: String) {
        let line = "\(time.string(from: Date())) \(text)"
        DispatchQueue.main.async { self.lines.append(line) }
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        log("Conectado (status \(status ?? 0)); recursos do celular=\(device.deviceSupportedFeatures), modos de espera=\(device.deviceCallHoldModes)")
    }
    func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) { log("Desconectado (status \(status ?? 0))") }
    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        log("SCO aberto (status \(status ?? 0))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.listAudioDevices() }
    }
    func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) { log("SCO fechado (status \(status ?? 0))") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isServiceAvailable value: NSNumber!) { log("Serviço disponível: \(value ?? 0)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive value: NSNumber!) { log("Ligação ativa: \(value ?? 0)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode value: NSNumber!) { log("Estado de chamada: \(value ?? 0)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, callHoldState value: NSNumber!) { log("Espera: \(value ?? 0)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, signalStrength value: NSNumber!) { log("Sinal: \(value ?? 0)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, batteryCharge value: NSNumber!) { log("Bateria: \(value ?? 0)") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, incomingCallFrom number: String!) { log("Ligação de: \(number ?? "?")") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, ringAttempt value: NSNumber!) { log("Tocando (\(value ?? 0))") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, currentCall call: [AnyHashable: Any]!) { log("Ligação atual: \(call ?? [:])") }
    func handsFree(_ device: IOBluetoothHandsFreeDevice!, unhandledResultCode code: String!) { log("Resposta não tratada: \(code ?? "")") }
}

struct SpikeView: View {
    @ObservedObject var spike: Spike

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Celular", selection: $spike.selected) {
                    ForEach(spike.devices, id: \.addressString) { device in
                        Text(device.name ?? device.addressString ?? "?").tag(device.addressString ?? "")
                    }
                }
                Button("Atualizar") { spike.refreshDevices() }
            }
            HStack {
                Button("Conectar viva-voz") { spike.connect() }
                Button("Desconectar") { spike.disconnect() }
                Button("Listar áudio") { spike.listAudioDevices() }
                Button("Ligações") { spike.callList() }
            }
            HStack {
                Button("Atender") { spike.answer() }
                Button("Desligar") { spike.hangUp() }
                Button("Áudio no Mac") { spike.audioToMac() }
                Button("Áudio no celular") { spike.audioToPhone() }
                Button("Abrir SCO") { spike.openSCO() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(spike.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { spike.refreshDevices() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let spike = Spike()
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Viva-voz Bluetooth (teste)"
        window.contentView = NSHostingView(rootView: SpikeView(spike: spike))
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
