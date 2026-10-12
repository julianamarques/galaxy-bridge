import AppKit

/// O app padrão para abrir links `tel:`. No macOS, quem atende esses links é o FaceTime até o usuário trocar.
enum CallLinks {
    private static let sample = URL(string: "tel:0")!

    static var isDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: sample)?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// O macOS pede a confirmação do usuário antes de trocar o app padrão.
    static func makeDefault() async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "tel")
    }
}
