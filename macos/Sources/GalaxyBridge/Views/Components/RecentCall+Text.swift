import BridgeProtocol
import Foundation

extension RecentCall {
    var date: Date { Date(timeIntervalSince1970: TimeInterval(time) / 1000) }

    var symbol: String {
        switch kind {
        case .incoming: "phone.arrow.down.left"
        case .outgoing: "phone.arrow.up.right"
        case .missed: "phone.arrow.down.left"
        case .declined: "phone.down"
        }
    }

    var kindLabel: String {
        switch kind {
        case .incoming: String(localized: "Recebida")
        case .outgoing: String(localized: "Feita")
        case .missed: String(localized: "Perdida")
        case .declined: String(localized: "Recusada")
        }
    }

    var when: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return String(localized: "Ontem") }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}
