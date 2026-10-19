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
    case contactsSearch(ContactsSearch)
    case contactsResults(ContactResults)
    case photoRequest(PhotoRequest)
    case photo(ContactPhoto)
    case notificationPosted(PhoneNotification)
    case notificationRemoved(NotificationKey)
    case notificationActive(NotificationKeys)
    case notificationAction(NotificationAction)
    case notificationDismiss(NotificationKey)
    case notificationFilter(NotificationFilter)
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
        case .contactsSearch: "contacts.search"
        case .contactsResults: "contacts.results"
        case .photoRequest: "photo.request"
        case .photo: "photo"
        case .notificationPosted: "notification.posted"
        case .notificationRemoved: "notification.removed"
        case .notificationActive: "notification.active"
        case .notificationAction: "notification.action"
        case .notificationDismiss: "notification.dismiss"
        case .notificationFilter: "notification.filter"
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
    public var contact: String?

    public init(call: String, state: State, direction: Direction, number: String? = nil, name: String? = nil, contact: String? = nil) {
        self.call = call
        self.state = state
        self.direction = direction
        self.number = number
        self.name = name
        self.contact = contact
    }
}

public struct CallID: Codable, Equatable, Sendable {
    public var call: String

    public init(call: String) {
        self.call = call
    }
}

public struct ContactsSearch: Codable, Equatable, Sendable {
    public var query: String
    public var limit: Int

    public init(query: String, limit: Int) {
        self.query = query
        self.limit = limit
    }
}

public struct Contact: Codable, Equatable, Identifiable, Sendable {
    public struct Number: Codable, Equatable, Sendable {
        public var number: String
        public var label: String?

        public init(number: String, label: String? = nil) {
            self.number = number
            self.label = label
        }
    }

    public var id: String
    public var name: String
    public var numbers: [Number]
    public var hasPhoto: Bool

    public init(id: String, name: String, numbers: [Number], hasPhoto: Bool) {
        self.id = id
        self.name = name
        self.numbers = numbers
        self.hasPhoto = hasPhoto
    }
}

public struct ContactResults: Codable, Equatable, Sendable {
    public var contacts: [Contact]

    public init(contacts: [Contact]) {
        self.contacts = contacts
    }
}

public struct PhotoRequest: Codable, Equatable, Sendable {
    public var contact: String

    public init(contact: String) {
        self.contact = contact
    }
}

public struct ContactPhoto: Codable, Equatable, Sendable {
    public var contact: String
    public var data: Data

    public init(contact: String, data: Data) {
        self.contact = contact
        self.data = data
    }
}

public struct PhoneNotification: Codable, Equatable, Sendable {
    public struct Action: Codable, Equatable, Sendable {
        public var id: Int
        public var title: String
        public var reply: Bool

        public init(id: Int, title: String, reply: Bool) {
            self.id = id
            self.title = title
            self.reply = reply
        }
    }

    public var key: String
    public var app: String
    public var appName: String
    public var title: String?
    public var text: String?
    public var time: Int64
    public var actions: [Action]
    public var silent: Bool
    public var icon: Data?

    public init(key: String, app: String, appName: String, title: String?, text: String?, time: Int64, actions: [Action], silent: Bool, icon: Data? = nil) {
        self.key = key
        self.app = app
        self.appName = appName
        self.title = title
        self.text = text
        self.time = time
        self.actions = actions
        self.silent = silent
        self.icon = icon
    }
}

public struct NotificationKey: Codable, Equatable, Sendable {
    public var key: String

    public init(key: String) {
        self.key = key
    }
}

public struct NotificationKeys: Codable, Equatable, Sendable {
    public var keys: [String]

    public init(keys: [String]) {
        self.keys = keys
    }
}

public struct NotificationAction: Codable, Equatable, Sendable {
    public var key: String
    public var action: Int
    public var reply: String?

    public init(key: String, action: Int, reply: String? = nil) {
        self.key = key
        self.action = action
        self.reply = reply
    }
}

public struct NotificationFilter: Codable, Equatable, Sendable {
    public var muted: [String]

    public init(muted: [String]) {
        self.muted = muted
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
        case "contacts.search": .contactsSearch(try container.decode(ContactsSearch.self, forKey: .body))
        case "contacts.results": .contactsResults(try container.decode(ContactResults.self, forKey: .body))
        case "photo.request": .photoRequest(try container.decode(PhotoRequest.self, forKey: .body))
        case "photo": .photo(try container.decode(ContactPhoto.self, forKey: .body))
        case "notification.posted": .notificationPosted(try container.decode(PhoneNotification.self, forKey: .body))
        case "notification.removed": .notificationRemoved(try container.decode(NotificationKey.self, forKey: .body))
        case "notification.active": .notificationActive(try container.decode(NotificationKeys.self, forKey: .body))
        case "notification.action": .notificationAction(try container.decode(NotificationAction.self, forKey: .body))
        case "notification.dismiss": .notificationDismiss(try container.decode(NotificationKey.self, forKey: .body))
        case "notification.filter": .notificationFilter(try container.decode(NotificationFilter.self, forKey: .body))
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
        case .contactsSearch(let body): try container.encode(body, forKey: .body)
        case .contactsResults(let body): try container.encode(body, forKey: .body)
        case .photoRequest(let body): try container.encode(body, forKey: .body)
        case .photo(let body): try container.encode(body, forKey: .body)
        case .notificationPosted(let body): try container.encode(body, forKey: .body)
        case .notificationRemoved(let body), .notificationDismiss(let body): try container.encode(body, forKey: .body)
        case .notificationActive(let body): try container.encode(body, forKey: .body)
        case .notificationAction(let body): try container.encode(body, forKey: .body)
        case .notificationFilter(let body): try container.encode(body, forKey: .body)
        case .error(let body): try container.encode(body, forKey: .body)
        case .unpair, .ping, .pong, .unknown: break
        }
    }
}
