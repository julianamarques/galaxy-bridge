import BridgeProtocol
import Foundation

@MainActor
final class FileBrowser: ObservableObject {
    static let windowID = "files"

    @Published private(set) var path = ""
    @Published private(set) var files: [PhoneFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var canGoBack = false

    var send: ((Message) -> String?)?
    var offer: ((URL, String) -> Bool)?

    private var request: String?
    private var history: [String] = []

    var components: [(name: String, path: String)] {
        let parts = path.split(separator: "/").map(String.init)
        return parts.indices.map { (parts[$0], parts[...$0].joined(separator: "/")) }
    }

    func open(_ path: String) {
        if path != self.path { history.append(self.path) }
        load(path)
    }

    func open(_ file: PhoneFile) {
        if file.folder {
            open(child(file))
        } else {
            download([file])
        }
    }

    func back() {
        guard let previous = history.popLast() else { return }
        load(previous)
    }

    func refresh() {
        load(path)
    }

    func download(_ files: [PhoneFile]) {
        for file in files where !file.folder {
            _ = send?(.filesGet(FilesList(path: child(file))))
        }
    }

    func upload(_ urls: [URL]) -> Bool {
        let files = urls.filter { !$0.hasDirectoryPath }
        return files.reduce(false) { sent, url in (offer?(url, path) ?? false) || sent }
    }

    func received(_ listing: FilesListing, replyTo: String?) {
        guard replyTo != nil, replyTo == request else { return }
        request = nil
        isLoading = false
        error = nil
        path = listing.path
        files = listing.files
    }

    func failed(_ message: String, replyTo: String?) -> Bool {
        guard replyTo != nil, replyTo == request else { return false }
        request = nil
        isLoading = false
        error = message
        return true
    }

    func uploaded() {
        guard request == nil, error == nil else { return }
        refresh()
    }

    func disconnected() {
        request = nil
        isLoading = false
        files = []
        error = String(localized: "O Galaxy não está conectado.")
    }

    private func load(_ path: String) {
        canGoBack = !history.isEmpty
        guard let id = send?(.filesList(FilesList(path: path))) else {
            return disconnected()
        }
        request = id
        isLoading = true
        if path != self.path {
            files = []
            self.path = path
        }
    }

    private func child(_ file: PhoneFile) -> String {
        path.isEmpty ? file.name : "\(path)/\(file.name)"
    }
}
