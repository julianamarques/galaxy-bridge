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

    @objc func openOnGalaxy(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let typed = pasteboard.string(forType: .string).flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let url = (urls + [typed].compactMap { $0 }).first(where: \.isWebLink) else {
            error.pointee = String(localized: "Nenhum link para abrir.") as NSString
            return
        }
        app.openOnPhone(url)
    }
}
