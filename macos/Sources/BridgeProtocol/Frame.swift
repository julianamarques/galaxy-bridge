import Foundation

/// Cada mensagem vai como 4 bytes de tamanho (big-endian) seguidos do JSON em UTF-8.
public enum Frame {
    public static let maxLength = 1 << 20

    public enum Failure: Error, Equatable {
        case tooLong(Int)
    }

    public static func encode(_ envelope: Envelope) throws -> Data {
        let body = try JSONEncoder().encode(envelope)
        guard body.count <= maxLength else { throw Failure.tooLong(body.count) }
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }
}

/// Junta os pedaços que chegam da rede e devolve as mensagens completas.
public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    /// Devolve o JSON de cada mensagem completa. Lança `Frame.Failure.tooLong` se um tamanho passar do limite,
    /// e então a conexão deve ser fechada.
    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var bodies: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length <= Frame.maxLength else { throw Frame.Failure.tooLong(length) }
            guard buffer.count >= 4 + length else { break }
            bodies.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return bodies
    }
}
