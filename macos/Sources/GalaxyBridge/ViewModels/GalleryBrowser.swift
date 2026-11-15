import AppKit
import BridgeProtocol
import Foundation

struct GalleryEntry: Identifiable {
    let id: String
    let name: String
    let date: Date
    let image: NSImage
    let duration: Int?
}

@MainActor
final class GalleryBrowser: ObservableObject {
    static let windowID = "gallery"
    private static let pageSize = 30

    @Published private(set) var albums: [GalleryAlbum] = []
    @Published private(set) var album: String?
    @Published private(set) var entries: [GalleryEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var error: String?
    @Published var selection: Set<String> = []

    var send: ((Message) -> String?)?

    private var request: String?
    private var albumsRequest: String?
    private var offset = 0

    func open() {
        albumsRequest = send?(.galleryAlbums)
        if entries.isEmpty { reload() }
    }

    func show(album: String?) {
        guard album != self.album else { return }
        self.album = album
        reload()
    }

    func reload() {
        entries = []
        selection = []
        offset = 0
        hasMore = true
        error = nil
        request = nil
        isLoading = false
        loadMore()
    }

    func loadMore() {
        guard !isLoading, hasMore else { return }
        guard let id = send?(.galleryRequest(GalleryRequest(limit: Self.pageSize, offset: offset, album: album, videos: true))) else {
            return disconnected()
        }
        request = id
        isLoading = true
    }

    func download(_ ids: Set<String>) {
        for id in ids { _ = send?(.galleryImport(GalleryID(id: id))) }
    }

    func received(_ photos: [GalleryPhoto], replyTo: String?) -> Bool {
        guard replyTo != nil, replyTo == request else { return false }
        request = nil
        isLoading = false
        offset += Self.pageSize
        hasMore = !photos.isEmpty
        entries += photos.compactMap { photo in
            NSImage(data: photo.thumbnail).map {
                GalleryEntry(id: photo.id, name: photo.name, date: Date(timeIntervalSince1970: TimeInterval(photo.time) / 1000), image: $0, duration: photo.duration)
            }
        }
        return true
    }

    func received(_ albums: [GalleryAlbum], replyTo: String?) {
        guard replyTo != nil, replyTo == albumsRequest else { return }
        albumsRequest = nil
        self.albums = albums
    }

    func failed(_ message: String, replyTo: String?) -> Bool {
        guard replyTo != nil, replyTo == request || replyTo == albumsRequest else { return false }
        request = nil
        albumsRequest = nil
        isLoading = false
        error = message
        return true
    }

    func disconnected() {
        request = nil
        albumsRequest = nil
        isLoading = false
        error = String(localized: "O Galaxy não está conectado.")
    }
}
