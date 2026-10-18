import Foundation
import GalaxyKit
import UserNotifications

@MainActor
final class CallNotifier: NSObject {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Log.phone.error("Notificações recusadas: \(error.localizedDescription, privacy: .public)") }
            else if !granted { Log.phone.info("O usuário não permitiu notificações") }
        }
    }

    func missed(call: String, caller: String, toVoicemail: Bool) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ligação perdida")
        content.body = toVoicemail ? String(localized: "\(caller) · correio de voz") : caller
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "missed-\(call)", content: content, trigger: nil))
    }
}

extension CallNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
