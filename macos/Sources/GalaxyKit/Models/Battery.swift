import Foundation

public struct Battery: Equatable, Sendable {
    public let level: Int
    public let isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }

    public init?(dumpsys output: String) {
        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard let level = values["level"].flatMap(Int.init) else { return nil }
        let status = values["status"].flatMap(Int.init)
        self.init(level: level, isCharging: status == 2 || status == 5)
    }
}
