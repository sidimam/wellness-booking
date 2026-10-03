import SwiftUI
import UIKit

/// Azioni rapide dal menu dell'icona (pressione lunga) — stesso schema di aMule Remote.
enum QuickAction: String, CaseIterable {
    case start = "com.sdimambro.wellness-booking.start"
    case stop = "com.sdimambro.wellness-booking.stop"
    case classes = "com.sdimambro.wellness-booking.classes"
    case bookings = "com.sdimambro.wellness-booking.bookings"

    var title: String {
        switch self {
        case .start: return String(localized: "Avvia")
        case .stop: return String(localized: "Ferma")
        case .classes: return String(localized: "Lezioni")
        case .bookings: return String(localized: "Prenotazioni")
        }
    }
    var systemImage: String {
        switch self {
        case .start: return "play.fill"; case .stop: return "stop.fill"
        case .classes: return "calendar"; case .bookings: return "checkmark.circle"
        }
    }
}

@MainActor
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()
    @Published var pending: QuickAction?
    @Published var selectedTab: Int = 0
}

final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }

    // Token APNs → gateway (notifiche push dal server di casa).
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await BookingEngine.shared.registerAPNS(token: hex) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in BookingEngine.shared.addLog("Registrazione push fallita: \(error.localizedDescription)", .warn) }
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem, let action = QuickAction(rawValue: item.type) {
            Task { @MainActor in QuickActionRouter.shared.pending = action }
        }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let action = QuickAction(rawValue: shortcutItem.type)
        Task { @MainActor in QuickActionRouter.shared.pending = action }
        completionHandler(action != nil)
    }
}

enum HomeScreenShortcuts {
    @MainActor static func install(running: Bool) {
        let actions: [QuickAction] = [running ? .stop : .start, .bookings, .classes]
        UIApplication.shared.shortcutItems = actions.map {
            UIApplicationShortcutItem(type: $0.rawValue, localizedTitle: $0.title, localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: $0.systemImage), userInfo: nil)
        }
    }
}
