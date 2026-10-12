import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String

    public var output: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
