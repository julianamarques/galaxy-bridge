import Foundation

extension Date {
    init(millis: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}
