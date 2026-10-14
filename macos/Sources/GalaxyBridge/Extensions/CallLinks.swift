import AppKit

enum CallLinks {
    private static let sample = URL(string: "tel:0")!

    static var isDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: sample)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault() async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "tel")
    }
}
