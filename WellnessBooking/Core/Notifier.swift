import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// Notifiche locali: normali e prioritarie (Time Sensitive, superano Focus/Non disturbare).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()
    private(set) var authorized = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive]) { [weak self] ok, _ in
            self?.authorized = ok
            #if os(iOS)
            if ok { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
            #endif
        }
    }

    /// Notifica immediata. `priority` = Time Sensitive (richiede la capability nell'entitlement).
    func notify(title: String, body: String, priority: Bool) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = priority ? .defaultCritical : .default
        if priority { c.interruptionLevel = .timeSensitive }
        c.threadIdentifier = "booking"
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Promemoria "apri l'app" 3 minuti prima di ogni apertura prenotazioni (per quando l'app è in background).
    func scheduleReminders(for items: [WatchItem], settings: AppSettings) {
        center.getPendingNotificationRequests { [weak self] reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix("reminder-") }
            self?.center.removePendingNotificationRequests(withIdentifiers: ids)
            for it in items where it.state == .pending {
                guard let fire = it.fireAt(settings: settings) else { continue }
                let when = fire.addingTimeInterval(-180)
                guard when > Date() else { continue }
                let c = UNMutableNotificationContent()
                c.title = String(localized: "Apertura prenotazioni tra 3 minuti")
                c.body = String(localized: "\(it.name) \(it.start.itDateTime): tieni Wellness Booking aperta in primo piano.")
                c.sound = .default
                c.interruptionLevel = settings.priorityNotifications ? .timeSensitive : .active
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: when)
                let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                self?.center.add(UNNotificationRequest(identifier: "reminder-\(it.id)", content: c, trigger: trig))
            }
        }
    }

    // Mostra le notifiche anche con app in primo piano.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum Haptics {
    static func success(enabled: Bool) {
        #if os(iOS)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func tap(enabled: Bool) {
        #if os(iOS)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
