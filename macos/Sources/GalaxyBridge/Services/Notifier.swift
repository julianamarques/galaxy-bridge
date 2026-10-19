import BridgeProtocol
import Foundation
import GalaxyKit
import UserNotifications

@MainActor
final class Notifier: NSObject {
    var onAction: ((String, Int, String?) -> Void)?
    var onDismiss: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var categories: [String: UNNotificationCategory] = [:]
    nonisolated private static let phonePrefix = "phone-"
    nonisolated private static let keyInfo = "key"
    private static let actionPrefix = "action-"

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

    func show(_ notification: PhoneNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title ?? notification.appName
        if notification.title != nil { content.subtitle = notification.appName }
        content.body = notification.text ?? ""
        content.threadIdentifier = notification.app
        content.userInfo = [Self.keyInfo: notification.key]
        content.categoryIdentifier = category(for: notification.actions)
        if !notification.silent { content.sound = .default }
        center.add(UNNotificationRequest(identifier: Self.phonePrefix + notification.key, content: content, trigger: nil))
    }

    func remove(_ key: String) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.phonePrefix + key])
    }

    func keepOnly(_ keys: [String]) {
        let active = Set(keys.map { Self.phonePrefix + $0 })
        Task {
            let delivered = await center.deliveredNotifications()
            let stale = delivered.map(\.request.identifier).filter { $0.hasPrefix(Self.phonePrefix) && !active.contains($0) }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    private func category(for actions: [PhoneNotification.Action]) -> String {
        let identifier = "phone:" + actions.map { "\($0.id)\($0.reply ? "r" : "a")\($0.title)" }.joined(separator: "|")
        guard categories[identifier] == nil else { return identifier }
        let notificationActions = actions.map { action -> UNNotificationAction in
            let id = Self.actionPrefix + String(action.id)
            return action.reply
                ? UNTextInputNotificationAction(identifier: id, title: action.title, options: [], textInputButtonTitle: String(localized: "Enviar"), textInputPlaceholder: "")
                : UNNotificationAction(identifier: id, title: action.title, options: [])
        }
        categories[identifier] = UNNotificationCategory(identifier: identifier, actions: notificationActions, intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories(Set(categories.values))
        return identifier
    }

    private func received(_ actionIdentifier: String, key: String, reply: String?) {
        if actionIdentifier == UNNotificationDismissActionIdentifier {
            onDismiss?(key)
        } else if actionIdentifier.hasPrefix(Self.actionPrefix), let action = Int(actionIdentifier.dropFirst(Self.actionPrefix.count)) {
            onAction?(key, action, reply)
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let key = response.notification.request.content.userInfo[Self.keyInfo] as? String else { return }
        let action = response.actionIdentifier
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run { received(action, key: key, reply: reply) }
    }
}
