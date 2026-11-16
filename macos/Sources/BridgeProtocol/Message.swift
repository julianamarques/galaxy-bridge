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
    case transferUpload(TransferFile)
    case transferOffer(TransferFile)
    case transferDownload(TransferID)
    case transferChunk(TransferChunk)
    case transferResult(TransferResult)
    case clipboard(Clipboard)
    case ring(Ring)
    case callsRecent(RecentCalls)
    case galleryRequest(GalleryRequest)
    case galleryResults(GalleryResults)
    case galleryImport(GalleryID)
    case link(Link)
    case mediaState(MediaState)
    case mediaControl(MediaControl)
    case dnd(DoNotDisturb)
    case filesList(FilesList)
    case filesListing(FilesListing)
    case filesGet(FilesList)
    case mirrorStart(MirrorStart)
    case mirrorState(MirrorState)
    case mirrorStream(MirrorStream)
    case mirrorTouch(MirrorTouch)
    case mirrorScroll(MirrorScroll)
    case mirrorKey(MirrorKey)
    case mirrorText(MirrorText)
    case galleryAlbums
    case galleryAlbumList(GalleryAlbums)
    case cameraCapture
    case mirrorStop
    case mirrorSync
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
        case .transferUpload: "transfer.upload"
        case .transferOffer: "transfer.offer"
        case .transferDownload: "transfer.download"
        case .transferChunk: "transfer.chunk"
        case .transferResult: "transfer.result"
        case .clipboard: "clipboard"
        case .ring: "ring"
        case .callsRecent: "calls.recent"
        case .galleryRequest: "gallery.request"
        case .galleryResults: "gallery.results"
        case .galleryImport: "gallery.import"
        case .link: "link"
        case .mediaState: "media.state"
        case .mediaControl: "media.control"
        case .dnd: "dnd"
        case .filesList: "files.list"
        case .filesListing: "files.listing"
        case .filesGet: "files.get"
        case .mirrorStart: "mirror.start"
        case .mirrorState: "mirror.state"
        case .mirrorStream: "mirror.stream"
        case .mirrorTouch: "mirror.touch"
        case .mirrorScroll: "mirror.scroll"
        case .mirrorKey: "mirror.key"
        case .mirrorText: "mirror.text"
        case .galleryAlbums: "gallery.albums"
        case .galleryAlbumList: "gallery.albumList"
        case .cameraCapture: "camera.capture"
        case .mirrorStop: "mirror.stop"
        case .mirrorSync: "mirror.sync"
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
    public var addresses: [String]?
    public var port: Int?

    public init(version: Int = protocolVersion, appVersion: String, name: String, model: String, addresses: [String]? = nil, port: Int? = nil) {
        self.version = version
        self.appVersion = appVersion
        self.name = name
        self.model = model
        self.addresses = addresses
        self.port = port
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

    public struct Accessory: Codable, Equatable, Identifiable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case headphones
            case watch
            case other
        }

        public var name: String
        public var battery: Int
        public var kind: Kind?

        public var id: String { name }

        public init(name: String, battery: Int, kind: Kind? = nil) {
            self.name = name
            self.battery = battery
            self.kind = kind
        }
    }

    public struct Storage: Codable, Equatable, Sendable {
        public var free: Int64
        public var total: Int64

        public init(free: Int64, total: Int64) {
            self.free = free
            self.total = total
        }
    }

    public var battery: Battery
    public var networkCountry: String?
    public var simCountry: String?
    public var carrier: String?
    public var signal: Int?
    public var network: String?
    public var wifi: Int?
    public var storage: Storage?
    public var dnd: Bool?
    public var accessories: [Accessory]?

    public init(
        battery: Battery,
        networkCountry: String? = nil,
        simCountry: String? = nil,
        carrier: String? = nil,
        signal: Int? = nil,
        network: String? = nil,
        wifi: Int? = nil,
        storage: Storage? = nil,
        dnd: Bool? = nil,
        accessories: [Accessory]? = nil
    ) {
        self.battery = battery
        self.networkCountry = networkCountry
        self.simCountry = simCountry
        self.carrier = carrier
        self.signal = signal
        self.network = network
        self.wifi = wifi
        self.storage = storage
        self.dnd = dnd
        self.accessories = accessories
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
    public var declined: Bool?

    public init(call: String, state: State, direction: Direction, number: String? = nil, name: String? = nil, contact: String? = nil, declined: Bool? = nil) {
        self.call = call
        self.state = state
        self.direction = direction
        self.number = number
        self.name = name
        self.contact = contact
        self.declined = declined
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
    public var image: Data?

    public init(key: String, app: String, appName: String, title: String?, text: String?, time: Int64, actions: [Action], silent: Bool, icon: Data? = nil, image: Data? = nil) {
        self.key = key
        self.app = app
        self.appName = appName
        self.title = title
        self.text = text
        self.time = time
        self.actions = actions
        self.silent = silent
        self.icon = icon
        self.image = image
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

public struct TransferFile: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var size: Int64
    public var mime: String?
    public var folder: String?
    public var capture: Bool?

    public init(id: String, name: String, size: Int64, mime: String? = nil, folder: String? = nil, capture: Bool? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.mime = mime
        self.folder = folder
        self.capture = capture
    }
}

public struct TransferID: Codable, Equatable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct TransferChunk: Codable, Equatable, Sendable {
    public var id: String
    public var data: Data

    public init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

public struct TransferResult: Codable, Equatable, Sendable {
    public var id: String
    public var ok: Bool
    public var message: String?

    public init(id: String, ok: Bool, message: String? = nil) {
        self.id = id
        self.ok = ok
        self.message = message
    }
}

public struct Clipboard: Codable, Equatable, Sendable {
    public static let maxLength = 100_000

    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct Ring: Codable, Equatable, Sendable {
    public var on: Bool

    public init(on: Bool) {
        self.on = on
    }
}

public struct RecentCall: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case incoming
        case outgoing
        case missed
        case declined
    }

    public var number: String?
    public var name: String?
    public var contact: String?
    public var kind: Kind
    public var time: Int64

    public var id: String { "\(time)|\(number ?? "")" }

    public init(number: String?, name: String? = nil, contact: String? = nil, kind: Kind, time: Int64) {
        self.number = number
        self.name = name
        self.contact = contact
        self.kind = kind
        self.time = time
    }
}

public struct RecentCalls: Codable, Equatable, Sendable {
    public var calls: [RecentCall]

    public init(calls: [RecentCall]) {
        self.calls = calls
    }
}

public struct GalleryRequest: Codable, Equatable, Sendable {
    public var limit: Int
    public var offset: Int?
    public var album: String?

    public init(limit: Int, offset: Int? = nil, album: String? = nil) {
        self.limit = limit
        self.offset = offset
        self.album = album
    }
}

public struct GalleryAlbum: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var count: Int

    public init(id: String, name: String, count: Int) {
        self.id = id
        self.name = name
        self.count = count
    }
}

public struct GalleryAlbums: Codable, Equatable, Sendable {
    public var albums: [GalleryAlbum]

    public init(albums: [GalleryAlbum]) {
        self.albums = albums
    }
}

public struct GalleryPhoto: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var time: Int64
    public var thumbnail: Data
    public var duration: Int?

    public init(id: String, name: String, time: Int64, thumbnail: Data, duration: Int? = nil) {
        self.id = id
        self.name = name
        self.time = time
        self.thumbnail = thumbnail
        self.duration = duration
    }
}

public struct GalleryResults: Codable, Equatable, Sendable {
    public var photos: [GalleryPhoto]
    public var more: Bool?

    public init(photos: [GalleryPhoto], more: Bool? = nil) {
        self.photos = photos
        self.more = more
    }
}

public struct GalleryID: Codable, Equatable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct Link: Codable, Equatable, Sendable {
    public var url: String

    public init(url: String) {
        self.url = url
    }
}

public struct MediaState: Codable, Equatable, Sendable {
    public var app: String?
    public var appName: String?
    public var title: String?
    public var artist: String?
    public var playing: Bool
    public var artwork: Data?

    public init(app: String? = nil, appName: String? = nil, title: String? = nil, artist: String? = nil, playing: Bool, artwork: Data? = nil) {
        self.app = app
        self.appName = appName
        self.title = title
        self.artist = artist
        self.playing = playing
        self.artwork = artwork
    }
}

public struct MediaControl: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case play
        case pause
        case next
        case previous
    }

    public var action: Action

    public init(action: Action) {
        self.action = action
    }
}

public struct DoNotDisturb: Codable, Equatable, Sendable {
    public var on: Bool

    public init(on: Bool) {
        self.on = on
    }
}

public struct FilesList: Codable, Equatable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct PhoneFile: Codable, Equatable, Identifiable, Sendable {
    public var name: String
    public var folder: Bool
    public var size: Int64
    public var modified: Int64

    public var id: String { name }

    public init(name: String, folder: Bool, size: Int64, modified: Int64) {
        self.name = name
        self.folder = folder
        self.size = size
        self.modified = modified
    }
}

public struct FilesListing: Codable, Equatable, Sendable {
    public var path: String
    public var files: [PhoneFile]
    public var truncated: Bool?

    public init(path: String, files: [PhoneFile], truncated: Bool? = nil) {
        self.path = path
        self.files = files
        self.truncated = truncated
    }
}

public struct MirrorStart: Codable, Equatable, Sendable {
    public var maxSize: Int?
    public var bitRate: Int
    public var audio: Bool?

    public init(maxSize: Int?, bitRate: Int, audio: Bool? = nil) {
        self.maxSize = maxSize
        self.bitRate = bitRate
        self.audio = audio
    }
}

public struct MirrorState: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case waiting
        case running
        case stopped
    }

    public var state: State
    public var control: Bool?
    public var message: String?

    public init(state: State, control: Bool? = nil, message: String? = nil) {
        self.state = state
        self.control = control
        self.message = message
    }
}

public struct MirrorStream: Codable, Equatable, Sendable {
    public var codec: String

    public init(codec: String) {
        self.codec = codec
    }
}

public struct MirrorTouch: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case down
        case move
        case up
    }

    public var action: Action
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(action: Action, x: Int, y: Int, width: Int, height: Int) {
        self.action = action
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MirrorScroll: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var dx: Double
    public var dy: Double

    public init(x: Int, y: Int, width: Int, height: Int, dx: Double, dy: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.dx = dx
        self.dy = dy
    }
}

public struct MirrorKey: Codable, Equatable, Sendable {
    public enum Key: String, Codable, Sendable {
        case back
        case home
        case recents
        case enter
        case delete
        case notifications
        case copy
        case cut
    }

    public var key: Key

    public init(key: Key) {
        self.key = key
    }
}

public struct MirrorText: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
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
        case "transfer.upload": .transferUpload(try container.decode(TransferFile.self, forKey: .body))
        case "transfer.offer": .transferOffer(try container.decode(TransferFile.self, forKey: .body))
        case "transfer.download": .transferDownload(try container.decode(TransferID.self, forKey: .body))
        case "transfer.chunk": .transferChunk(try container.decode(TransferChunk.self, forKey: .body))
        case "transfer.result": .transferResult(try container.decode(TransferResult.self, forKey: .body))
        case "clipboard": .clipboard(try container.decode(Clipboard.self, forKey: .body))
        case "ring": .ring(try container.decode(Ring.self, forKey: .body))
        case "calls.recent": .callsRecent(try container.decode(RecentCalls.self, forKey: .body))
        case "gallery.request": .galleryRequest(try container.decode(GalleryRequest.self, forKey: .body))
        case "gallery.results": .galleryResults(try container.decode(GalleryResults.self, forKey: .body))
        case "gallery.import": .galleryImport(try container.decode(GalleryID.self, forKey: .body))
        case "link": .link(try container.decode(Link.self, forKey: .body))
        case "media.state": .mediaState(try container.decode(MediaState.self, forKey: .body))
        case "media.control": .mediaControl(try container.decode(MediaControl.self, forKey: .body))
        case "dnd": .dnd(try container.decode(DoNotDisturb.self, forKey: .body))
        case "files.list": .filesList(try container.decode(FilesList.self, forKey: .body))
        case "files.listing": .filesListing(try container.decode(FilesListing.self, forKey: .body))
        case "files.get": .filesGet(try container.decode(FilesList.self, forKey: .body))
        case "mirror.start": .mirrorStart(try container.decode(MirrorStart.self, forKey: .body))
        case "mirror.state": .mirrorState(try container.decode(MirrorState.self, forKey: .body))
        case "mirror.stream": .mirrorStream(try container.decode(MirrorStream.self, forKey: .body))
        case "mirror.touch": .mirrorTouch(try container.decode(MirrorTouch.self, forKey: .body))
        case "mirror.scroll": .mirrorScroll(try container.decode(MirrorScroll.self, forKey: .body))
        case "mirror.key": .mirrorKey(try container.decode(MirrorKey.self, forKey: .body))
        case "mirror.text": .mirrorText(try container.decode(MirrorText.self, forKey: .body))
        case "gallery.albums": .galleryAlbums
        case "gallery.albumList": .galleryAlbumList(try container.decode(GalleryAlbums.self, forKey: .body))
        case "camera.capture": .cameraCapture
        case "mirror.stop": .mirrorStop
        case "mirror.sync": .mirrorSync
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
        case .transferUpload(let body), .transferOffer(let body): try container.encode(body, forKey: .body)
        case .transferDownload(let body): try container.encode(body, forKey: .body)
        case .transferChunk(let body): try container.encode(body, forKey: .body)
        case .transferResult(let body): try container.encode(body, forKey: .body)
        case .clipboard(let body): try container.encode(body, forKey: .body)
        case .ring(let body): try container.encode(body, forKey: .body)
        case .callsRecent(let body): try container.encode(body, forKey: .body)
        case .galleryRequest(let body): try container.encode(body, forKey: .body)
        case .galleryResults(let body): try container.encode(body, forKey: .body)
        case .galleryImport(let body): try container.encode(body, forKey: .body)
        case .link(let body): try container.encode(body, forKey: .body)
        case .mediaState(let body): try container.encode(body, forKey: .body)
        case .mediaControl(let body): try container.encode(body, forKey: .body)
        case .dnd(let body): try container.encode(body, forKey: .body)
        case .filesList(let body), .filesGet(let body): try container.encode(body, forKey: .body)
        case .filesListing(let body): try container.encode(body, forKey: .body)
        case .mirrorStart(let body): try container.encode(body, forKey: .body)
        case .mirrorState(let body): try container.encode(body, forKey: .body)
        case .mirrorStream(let body): try container.encode(body, forKey: .body)
        case .mirrorTouch(let body): try container.encode(body, forKey: .body)
        case .mirrorScroll(let body): try container.encode(body, forKey: .body)
        case .mirrorKey(let body): try container.encode(body, forKey: .body)
        case .mirrorText(let body): try container.encode(body, forKey: .body)
        case .error(let body): try container.encode(body, forKey: .body)
        case .galleryAlbumList(let body): try container.encode(body, forKey: .body)
        case .unpair, .ping, .pong, .mirrorStop, .mirrorSync, .galleryAlbums, .cameraCapture, .unknown: break
        }
    }
}
