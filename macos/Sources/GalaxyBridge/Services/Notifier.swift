import AppKit
import BridgeProtocol
import Foundation
import GalaxyKit
import UserNotifications

@MainActor
final class Notifier: NSObject {
    var send: ((Message) -> Void)?
    var callBack: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var categories: [String: UNNotificationCategory] = [:]
    nonisolated private static let phonePrefix = "phone-"
    nonisolated private static let filePrefix = "file-"
    nonisolated private static let fileInfo = "path"
    nonisolated private static let numberInfo = "number"
    nonisolated private static let callBackAction = "call-back"
    private static let missedCategory = "missed"
    private static let clipboardPreview = 120
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

    func missed(call: String, caller: String, number: String?, toVoicemail: Bool) {
        let body = toVoicemail ? String(localized: "\(caller) · correio de voz") : caller
        let content = content(title: String(localized: "Ligação perdida"), body: body, sound: true)
        if let number {
            registerMissedCategory()
            content.categoryIdentifier = Self.missedCategory
            content.userInfo = [Self.numberInfo: number]
        }
        center.add(UNNotificationRequest(identifier: "missed-\(call)", content: content, trigger: nil))
    }

    private func registerMissedCategory() {
        guard categories[Self.missedCategory] == nil else { return }
        let action = UNNotificationAction(identifier: Self.callBackAction, title: String(localized: "Ligar de Volta"), options: [])
        categories[Self.missedCategory] = UNNotificationCategory(identifier: Self.missedCategory, actions: [action], intentIdentifiers: [], options: [])
        center.setNotificationCategories(Set(categories.values))
    }

    func fileReceived(_ file: URL) {
        post(Self.filePrefix + UUID().uuidString, title: String(localized: "Recebido do Galaxy"), body: file.lastPathComponent, sound: true, userInfo: [Self.fileInfo: file.path])
    }

    func photoCaptured(_ file: URL) {
        post(Self.filePrefix + UUID().uuidString, title: String(localized: "Foto do Galaxy copiada"), body: String(localized: "Cole com ⌘V. Ela também está em Downloads."), sound: true, userInfo: [Self.fileInfo: file.path])
    }

    func fileSent(_ name: String, ok: Bool) {
        let title = ok ? String(localized: "Enviado para o Galaxy") : String(localized: "Não foi possível enviar para o Galaxy")
        post(Self.filePrefix + UUID().uuidString, title: title, body: name)
    }

    func battery(_ title: String, body: String, sound: Bool) {
        post("battery", title: title, body: body, sound: sound)
    }

    func clipboard(_ title: String, text: String) {
        post("clipboard", title: title, body: String(text.prefix(Self.clipboardPreview)))
    }

    private func post(_ id: String, title: String, body: String, sound: Bool = false, userInfo: [AnyHashable: Any] = [:]) {
        let content = content(title: title, body: body, sound: sound)
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func content(title: String, body: String, sound: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        return content
    }

    func show(_ notification: PhoneNotification, icon: URL?) {
        let content = UNMutableNotificationContent()
        content.title = notification.title ?? notification.appName
        if notification.title != nil { content.subtitle = notification.appName }
        content.body = notification.text ?? ""
        content.threadIdentifier = notification.app
        content.categoryIdentifier = category(for: notification.actions)
        if !notification.silent { content.sound = .default }
        if let icon, let attachment = Self.attachment(copying: icon) { content.attachments = [attachment] }
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

    private static func attachment(copying icon: URL) -> UNNotificationAttachment? {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        guard (try? FileManager.default.copyItem(at: icon, to: copy)) != nil else { return nil }
        guard let attachment = try? UNNotificationAttachment(identifier: "icon", url: copy) else {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
        return attachment
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
            send?(.notificationDismiss(NotificationKey(key: key)))
        } else if actionIdentifier.hasPrefix(Self.actionPrefix), let action = Int(actionIdentifier.dropFirst(Self.actionPrefix.count)) {
            send?(.notificationAction(NotificationAction(key: key, action: action, reply: reply)))
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
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        if response.actionIdentifier == Self.callBackAction {
            guard let number = userInfo[Self.numberInfo] as? String else { return }
            await MainActor.run { callBack?(number) }
            return
        }
        if identifier.hasPrefix(Self.filePrefix), response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let path = response.notification.request.content.userInfo[Self.fileInfo] as? String {
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            return
        }
        guard identifier.hasPrefix(Self.phonePrefix) else { return }
        let key = String(identifier.dropFirst(Self.phonePrefix.count))
        let action = response.actionIdentifier
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run { received(action, key: key, reply: reply) }
    }
}
