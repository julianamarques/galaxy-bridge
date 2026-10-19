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

final class IncomingTransfer {
    let file: TransferFile
    let url: URL
    private let handle: FileHandle
    private var received: Int64 = 0

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

    init(file: TransferFile, url: URL) {
        self.file = file
        self.url = url
    }

    @MainActor
    func stream(on connection: BridgeConnection) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return connection.close() }
        let id = file.id
        func next() {
            guard let data = try? handle.read(upToCount: Transfer.chunkSize), !data.isEmpty else {
                try? handle.close()
                return
            }
            connection.send(Envelope(.transferChunk(TransferChunk(id: id, data: data))), then: next)
        }
        next()
    }
}
