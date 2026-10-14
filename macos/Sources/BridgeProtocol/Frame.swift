import Foundation

public enum Frame {
    public static let maxLength = 1 << 20
    private static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    public enum Failure: Error, Equatable {
        case tooLong(Int)
    }

    public static func encode(_ envelope: Envelope) throws -> Data {
        let body = try encoder.encode(envelope)
        guard body.count <= maxLength else { throw Failure.tooLong(body.count) }
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }
}

public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var bodies: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length <= Frame.maxLength else { throw Frame.Failure.tooLong(length) }
            guard buffer.count >= 4 + length else { break }
            let start = buffer.startIndex
            bodies.append(buffer.subdata(in: start + 4 ..< start + 4 + length))
            buffer.removeSubrange(start ..< start + 4 + length)
        }
        return bodies
    }
}
