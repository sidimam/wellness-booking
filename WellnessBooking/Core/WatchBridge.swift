import Foundation
import WatchConnectivity

/// Snapshot leggero inviato ad Apple Watch.
struct WatchSnapshot: Codable {
    struct Entry: Codable, Identifiable {
        var id: String
        var name: String
        var start: Date
        var state: String
        var symbol: String
        var message: String
        var places: Int?
    }
    var running: Bool
    var updated: Date
    var entries: [Entry]
}

/// Ponte iPhone ⇄ Apple Watch (WatchConnectivity): stato lezioni e comandi Avvia/Ferma/Prenota ora.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let s = session else { return }
        s.delegate = self
        s.activate()
    }

    func push(items: [WatchItem], running: Bool) {
        guard let s = session, s.activationState == .activated else { return }
        let snap = WatchSnapshot(running: running, updated: Date(), entries: items
            .filter { !$0.state.isTerminal || $0.start > Date().addingTimeInterval(-3600) }
            .prefix(12)
            .map { .init(id: $0.id, name: $0.name, start: $0.start, state: $0.state.label, symbol: $0.state.symbol,
                         message: $0.lastMessage, places: $0.availablePlaces) })
        guard let data = try? JSONEncoder().encode(snap) else { return }
        try? s.updateApplicationContext(["snapshot": data])
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            let e = BookingEngine.shared
            self.push(items: e.items, running: e.isRunning)
        }
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            let e = BookingEngine.shared
            switch message["cmd"] as? String {
            case "start": e.start()
            case "stop": e.stop()
            case "refresh": await e.refreshClasses()
            case "retry":
                if let id = message["id"] as? String, let it = e.items.first(where: { $0.id == id }) { e.retry(it) }
            default: break
            }
            self.push(items: e.items, running: e.isRunning)
            replyHandler(["ok": true, "running": e.isRunning])
        }
    }
}
