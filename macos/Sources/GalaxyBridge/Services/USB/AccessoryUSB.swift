import Foundation
import GalaxyKit
import IOKit
import IOKit.usb
import IOUSBHost

@MainActor
final class AccessoryUSB {
    nonisolated static let manufacturer = "Galaxy Bridge"
    nonisolated static let model = "Galaxy Bridge"
    private static let googleVendor = 0x18D1
    private static let accessoryProducts = Array(0x2D00...0x2D05)
    private static let phoneVendors: Set<Int> = [0x04E8]
    nonisolated private static let switchAttempts = 5
    nonisolated private static let switchRetryDelay: TimeInterval = 1
    private static let reopenAttempts = 3
    private static let reopenDelay: Duration = .seconds(1)
    nonisolated private static let strings = [
        manufacturer,
        model,
        "Galaxy Bridge para Mac",
        "1",
        "https://play.google.com/store/apps/details?id=com.julianamarques.galaxybridge",
        "1",
    ]

    var isEnabled: () -> Bool = { false }
    var port: () -> UInt16? = { nil }

    private let switchQueue = DispatchQueue(label: "GalaxyBridge.usb.switch")
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var callbacks: [Unmanaged<Callback>] = []
    private var link: AccessoryLink?
    private var accessory: io_service_t = 0
    private var switched: Set<UInt64> = []

    func start() {
        guard notifyPort == nil, let notifyPort = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.notifyPort = notifyPort
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(), .defaultMode)
        watch(IOServiceMatching("IOUSBHostDevice")) { usb, service in usb.deviceAppeared(service) }
        let interfaces = IOUSBHostInterface.__createMatchingDictionary(
            withVendorID: Self.googleVendor as NSNumber, productID: nil, bcdDevice: nil, interfaceNumber: 0,
            configurationValue: 1, interfaceClass: nil, interfaceSubclass: nil, interfaceProtocol: nil,
            speed: nil, productIDArray: Self.accessoryProducts.map { $0 as NSNumber }
        ).takeRetainedValue()
        watch(interfaces) { usb, service in usb.accessoryAppeared(service) }
    }

    func stop() {
        link?.close()
        link = nil
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        callbacks.forEach { $0.release() }
        callbacks = []
        forgetAccessory()
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
    }

    func retry() {
        guard link == nil, isEnabled() else { return }
        switched.removeAll()
        stop()
        start()
    }

    private func watch(_ matching: CFDictionary, _ handler: @escaping (AccessoryUSB, io_service_t) -> Void) {
        guard let notifyPort else { return }
        let box = Unmanaged.passRetained(Callback(owner: self, handler: handler))
        var iterator: io_iterator_t = 0
        let result = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matching, { refcon, iterator in
            guard let refcon else { return }
            let callback = Unmanaged<Callback>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { callback.drain(iterator) }
        }, box.toOpaque(), &iterator)
        guard result == KERN_SUCCESS else { return box.release() }
        iterators.append(iterator)
        callbacks.append(box)
        MainActor.assumeIsolated { box.takeUnretainedValue().drain(iterator) }
    }

    private func deviceAppeared(_ service: io_service_t) {
        guard isEnabled(), let vendor = Self.property(service, "idVendor") as? Int, Self.phoneVendors.contains(vendor),
              let product = Self.property(service, "USB Product Name") as? String, product.localizedCaseInsensitiveContains("Android")
        else { return }
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        guard switched.insert(id).inserted else { return }
        IOObjectRetain(service)
        switchQueue.async {
            defer { IOObjectRelease(service) }
            for attempt in 1...Self.switchAttempts {
                do {
                    try Self.switchToAccessory(service)
                    Log.connection.info("Celular no cabo: pedindo o modo acessório")
                    return
                } catch where attempt < Self.switchAttempts {
                    Thread.sleep(forTimeInterval: Self.switchRetryDelay)
                } catch {
                    Log.connection.info("O celular no cabo não aceitou o modo acessório: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func accessoryAppeared(_ service: io_service_t) {
        forgetAccessory()
        IOObjectRetain(service)
        accessory = service
        guard link == nil else { return }
        _ = open(service)
    }

    private func open(_ service: io_service_t) -> Bool {
        guard let port = port() else { return false }
        do {
            let interface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
            let link = try AccessoryLink(interface: interface, port: port)
            link.onClose = { [weak self, weak link] in
                guard let self, self.link === link else { return }
                self.link = nil
                Log.connection.info("Cabo USB desconectado")
                self.reopen()
            }
            self.link = link
            link.start()
            Log.connection.info("Cabo USB conectado ao Galaxy")
            return true
        } catch {
            Log.connection.error("Não foi possível abrir o cabo USB: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func reopen() {
        Task { [weak self] in
            for _ in 0..<Self.reopenAttempts {
                try? await Task.sleep(for: Self.reopenDelay)
                guard let self, self.link == nil, self.accessory != 0, self.isEnabled() else { return }
                if self.open(self.accessory) { return }
            }
            self?.forgetAccessory()
        }
    }

    private func forgetAccessory() {
        guard accessory != 0 else { return }
        IOObjectRelease(accessory)
        accessory = 0
    }

    private nonisolated static func switchToAccessory(_ service: io_service_t) throws {
        let device = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        defer { device.destroy() }
        let version = NSMutableData(length: 2)!
        try device.__send(request(0xC0, 51, length: 2), data: version, bytesTransferred: nil, completionTimeout: 2)
        let protocolVersion = version.bytes.load(as: UInt16.self)
        guard protocolVersion >= 1 else { throw ToolError.failed("AOA \(protocolVersion)") }
        for (index, text) in strings.enumerated() {
            let data = NSMutableData(data: Data(text.utf8) + [0])
            try device.__send(request(0x40, 52, index: UInt16(index), length: UInt16(data.length)), data: data, bytesTransferred: nil, completionTimeout: 2)
        }
        try device.__send(request(0x40, 53, length: 0), data: nil, bytesTransferred: nil, completionTimeout: 2)
    }

    private nonisolated static func request(_ type: UInt8, _ request: UInt8, index: UInt16 = 0, length: UInt16) -> IOUSBDeviceRequest {
        IOUSBDeviceRequest(bmRequestType: type, bRequest: request, wValue: 0, wIndex: index, wLength: length)
    }

    private nonisolated static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private final class Callback {
        weak var owner: AccessoryUSB?
        let handler: (AccessoryUSB, io_service_t) -> Void

        init(owner: AccessoryUSB, handler: @escaping (AccessoryUSB, io_service_t) -> Void) {
            self.owner = owner
            self.handler = handler
        }

        @MainActor
        func drain(_ iterator: io_iterator_t) {
            while case let service = IOIteratorNext(iterator), service != 0 {
                if let owner { handler(owner, service) }
                IOObjectRelease(service)
            }
        }
    }
}
