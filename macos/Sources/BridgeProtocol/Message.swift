import Foundation

public let protocolVersion = 1

public struct Envelope: Equatable, Sendable {
    public var message: Message
    public var id: String?
    public var replyTo: String?

    public init(_ message: Message, id: String? = nil, replyTo: String? = nil) {
        self.message = message
        self.id = id
        self.replyTo = replyTo
    }
}

public enum Message: Equatable, Sendable {
    case hello(Hello)
    case pairRequest(PairRequest)
    case pairAccepted(PairAccepted)
    case pairRejected(PairRejected)
    case unpair
    case status(PhoneStatus)
    case callPlace(CallPlace)
    case callState(CallState)
    case callAnswer(CallID)
    case callDecline(CallID)
    case callEnd(CallID)
    case error(BridgeError)
    case ping
    case pong
    case unknown(type: String)

    public var type: String {
        switch self {
        case .hello: "hello"
        case .pairRequest: "pair.request"
        case .pairAccepted: "pair.accepted"
        case .pairRejected: "pair.rejected"
        case .unpair: "unpair"
        case .status: "status"
        case .callPlace: "call.place"
        case .callState: "call.state"
        case .callAnswer: "call.answer"
        case .callDecline: "call.decline"
        case .callEnd: "call.end"
        case .error: "error"
        case .ping: "ping"
        case .pong: "pong"
        case .unknown(let type): type
        }
    }
}

public struct Hello: Codable, Equatable, Sendable {
    public var version: Int
    public var appVersion: String
    public var name: String
    public var model: String

    public init(version: Int = protocolVersion, appVersion: String, name: String, model: String) {
        self.version = version
        self.appVersion = appVersion
        self.name = name
        self.model = model
    }
}

public struct PairRequest: Codable, Equatable, Sendable {
    public var secret: String
    public var name: String
    public var model: String

    public init(secret: String, name: String, model: String) {
        self.secret = secret
        self.name = name
        self.model = model
    }
}

public struct PairAccepted: Codable, Equatable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct PairRejected: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case expired
        case invalid
    }

    public var reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

public struct PhoneStatus: Codable, Equatable, Sendable {
    public struct Battery: Codable, Equatable, Sendable {
        public var level: Int
        public var charging: Bool

        public init(level: Int, charging: Bool) {
            self.level = level
            self.charging = charging
        }
    }

    public var battery: Battery
    public var networkCountry: String?
    public var simCountry: String?

    public init(battery: Battery, networkCountry: String? = nil, simCountry: String? = nil) {
        self.battery = battery
        self.networkCountry = networkCountry
        self.simCountry = simCountry
    }
}

public struct CallPlace: Codable, Equatable, Sendable {
    public var number: String

    public init(number: String) {
        self.number = number
    }
}

public struct CallState: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case ringing
        case active
        case voicemail
        case ended
    }

    public enum Direction: String, Codable, Sendable {
        case incoming
        case outgoing
    }

    public var call: String
    public var state: State
    public var direction: Direction
    public var number: String?
    public var name: String?

    public init(call: String, state: State, direction: Direction, number: String? = nil, name: String? = nil) {
        self.call = call
        self.state = state
        self.direction = direction
        self.number = number
        self.name = name
    }
}

public struct CallID: Codable, Equatable, Sendable {
    public var call: String

    public init(call: String) {
        self.call = call
    }
}

public struct BridgeError: Codable, Equatable, Sendable, Error {
    public enum Code: String, Codable, Sendable {
        case version
        case permission
        case failed
    }

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

extension Envelope: Codable {
    private enum Keys: String, CodingKey {
        case type, id, replyTo, body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        replyTo = try container.decodeIfPresent(String.self, forKey: .replyTo)
        message = switch type {
        case "hello": .hello(try container.decode(Hello.self, forKey: .body))
        case "pair.request": .pairRequest(try container.decode(PairRequest.self, forKey: .body))
        case "pair.accepted": .pairAccepted(try container.decode(PairAccepted.self, forKey: .body))
        case "pair.rejected": .pairRejected(try container.decode(PairRejected.self, forKey: .body))
        case "unpair": .unpair
        case "status": .status(try container.decode(PhoneStatus.self, forKey: .body))
        case "call.place": .callPlace(try container.decode(CallPlace.self, forKey: .body))
        case "call.state": .callState(try container.decode(CallState.self, forKey: .body))
        case "call.answer": .callAnswer(try container.decode(CallID.self, forKey: .body))
        case "call.decline": .callDecline(try container.decode(CallID.self, forKey: .body))
        case "call.end": .callEnd(try container.decode(CallID.self, forKey: .body))
        case "error": .error(try container.decode(BridgeError.self, forKey: .body))
        case "ping": .ping
        case "pong": .pong
        default: .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(message.type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        switch message {
        case .hello(let body): try container.encode(body, forKey: .body)
        case .pairRequest(let body): try container.encode(body, forKey: .body)
        case .pairAccepted(let body): try container.encode(body, forKey: .body)
        case .pairRejected(let body): try container.encode(body, forKey: .body)
        case .status(let body): try container.encode(body, forKey: .body)
        case .callPlace(let body): try container.encode(body, forKey: .body)
        case .callState(let body): try container.encode(body, forKey: .body)
        case .callAnswer(let body), .callDecline(let body), .callEnd(let body): try container.encode(body, forKey: .body)
        case .error(let body): try container.encode(body, forKey: .body)
        case .unpair, .ping, .pong, .unknown: break
        }
    }
}
