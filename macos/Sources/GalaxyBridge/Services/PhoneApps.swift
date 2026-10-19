import AppKit
import Foundation

@MainActor
final class PhoneApps: ObservableObject {
    struct App: Codable, Identifiable, Hashable {
        let id: String
        var name: String
    }

    @Published private(set) var apps: [App]
    @Published private(set) var muted: Set<String>
    var onMutedChange: ((Set<String>) -> Void)?

    private let iconDirectory: URL
    private static let appsKey = "phoneApps"
    private static let mutedKey = "mutedPhoneApps"

    init(iconDirectory: URL) {
        self.iconDirectory = iconDirectory
        apps = UserDefaults.standard.data(forKey: Self.appsKey)
            .flatMap { try? JSONDecoder().decode([App].self, from: $0) } ?? []
        muted = Set(UserDefaults.standard.stringArray(forKey: Self.mutedKey) ?? [])
    }

    func remember(_ id: String, name: String) {
        if let index = apps.firstIndex(where: { $0.id == id }) {
            guard apps[index].name != name else { return }
            apps[index].name = name
        } else {
            apps.append(App(id: id, name: name))
            apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(apps), forKey: Self.appsKey)
    }

    func isMuted(_ id: String) -> Bool { muted.contains(id) }

    func setMuted(_ id: String, _ isMuted: Bool) {
        if isMuted { muted.insert(id) } else { muted.remove(id) }
        UserDefaults.standard.set(muted.sorted(), forKey: Self.mutedKey)
        onMutedChange?(muted)
    }

    func iconFile(_ id: String) -> URL? {
        let file = iconDirectory.appendingPathComponent(id + ".png")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    func icon(_ id: String) -> NSImage? {
        iconFile(id).flatMap { NSImage(contentsOf: $0) }
    }

    func saveIcon(_ id: String, data: Data) {
        try? FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        try? data.write(to: iconDirectory.appendingPathComponent(id + ".png"), options: .atomic)
        objectWillChange.send()
    }
}
