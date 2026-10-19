import AppKit

@MainActor
final class SendToGalaxyService: NSObject {
    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    @objc func sendToGalaxy(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(localized: "Nenhum arquivo para enviar.") as NSString
            return
        }
        app.sendFiles(urls)
    }
}
