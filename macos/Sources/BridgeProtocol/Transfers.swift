import Foundation

public enum Transfer {
    public static let chunkSize = 256 * 1024

    public static func safeName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" || $0 == ":" }).last.map(String.init) ?? ""
        let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let cleaned = String(trimmed.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return cleaned.isEmpty ? "Arquivo do Galaxy" : String(cleaned.prefix(200))
    }

    public static func place(_ file: URL, named name: String, in directory: URL) throws -> URL {
        let safe = safeName(name)
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        var target = directory.appendingPathComponent(safe)
        var copy = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let numbered = "\(base) (\(copy))"
            target = directory.appendingPathComponent(ext.isEmpty ? numbered : numbered + "." + ext)
            copy += 1
        }
        try FileManager.default.moveItem(at: file, to: target)
        return target
    }
}

public enum TransferOutcome: Sendable {
    case received(URL, name: String)
    case sent(name: String, ok: Bool)
    case interrupted
}

public struct TransferProgress: Identifiable, Equatable, Sendable {
    public enum Direction: Sendable {
        case toPhone
        case fromPhone
    }

    public let id: String
    public let name: String
    public let direction: Direction
    public var done: Int64
    public let total: Int64

    public var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    public var percent: Int { Int(fraction * 100) }

    public init(id: String, name: String, direction: Direction, done: Int64, total: Int64) {
        self.id = id
        self.name = name
        self.direction = direction
        self.done = done
        self.total = total
    }

    public init(_ file: TransferFile, direction: Direction, done: Int64) {
        self.init(id: file.id, name: file.name, direction: direction, done: done, total: file.size)
    }
}

final class TransferSession {
    enum Kind {
        case receiving(IncomingTransfer)
        case sending(OutgoingTransfer)
    }

    var kind: Kind?
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiated, .idleSystemSleepDisabled],
        reason: "Transferindo um arquivo com o celular"
    )

    func end() {
        ProcessInfo.processInfo.endActivity(activity)
    }
}

final class IncomingTransfer {
    let file: TransferFile
    let url: URL
    private let handle: FileHandle
    private(set) var received: Int64 = 0

    init?(_ file: TransferFile) {
        guard file.size >= 0 else { return nil }
        url = FileManager.default.temporaryDirectory.appendingPathComponent("galaxy-bridge-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url)
        else { return nil }
        self.file = file
        self.handle = handle
    }

    var isComplete: Bool { received == file.size }

    func write(_ data: Data) throws {
        guard received + Int64(data.count) <= file.size else { throw CocoaError(.fileWriteUnknown) }
        try handle.write(contentsOf: data)
        received += Int64(data.count)
        if isComplete { try handle.close() }
    }

    func discard() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }
}

final class OutgoingTransfer {
    let file: TransferFile
    let url: URL
    private(set) var started = false

    init(file: TransferFile, url: URL) {
        self.file = file
        self.url = url
    }

    @MainActor
    func stream(on connection: BridgeConnection, progress: @escaping @MainActor (Int64) -> Void) {
        started = true
        guard let handle = try? FileHandle(forReadingFrom: url) else { return connection.close() }
        let id = file.id
        var sent: Int64 = 0
        func next() {
            guard let data = try? handle.read(upToCount: Transfer.chunkSize), !data.isEmpty else {
                try? handle.close()
                return
            }
            connection.send(Envelope(.transferChunk(TransferChunk(id: id, data: data)))) {
                sent += Int64(data.count)
                progress(sent)
                next()
            }
        }
        next()
    }
}
