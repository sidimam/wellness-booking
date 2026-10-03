import SwiftUI
import WatchConnectivity

/// App Apple Watch: stato delle lezioni seguite + comandi Avvia/Ferma/Aggiorna.
/// Le notifiche (prenotata, posto libero) arrivano dall'iPhone tramite il mirroring di iOS.
@main
struct WellnessBookingWatchApp: App {
    @StateObject private var store = WatchStore.shared
    var body: some Scene {
        WindowGroup { WatchRootView().environmentObject(store) }
    }
}

struct WatchSnapshot: Codable {
    struct Entry: Codable, Identifiable {
        var id: String; var name: String; var start: Date; var state: String; var symbol: String; var message: String; var places: Int?
    }
    var running: Bool
    var updated: Date
    var entries: [Entry]
}

@MainActor
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()
    @Published var snapshot: WatchSnapshot?
    @Published var reachable = false
    @Published var busy = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        if let d = WCSession.default.receivedApplicationContext["snapshot"] as? Data { decode(d) }
    }

    private func decode(_ d: Data) {
        if let s = try? JSONDecoder().decode(WatchSnapshot.self, from: d) { snapshot = s }
    }

    func send(_ cmd: String, id: String? = nil) {
        guard WCSession.default.isReachable else { return }
        busy = true
        var msg: [String: Any] = ["cmd": cmd]
        if let id { msg["id"] = id }
        WCSession.default.sendMessage(msg, replyHandler: { _ in Task { @MainActor in self.busy = false } },
                                      errorHandler: { _ in Task { @MainActor in self.busy = false } })
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.reachable = session.isReachable
            if let d = session.receivedApplicationContext["snapshot"] as? Data { self.decode(d) }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachable = session.isReachable }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let d = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor in self.decode(d) }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore
    private let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "EEE d MMM HH:mm"; return f
    }()

    var body: some View {
        NavigationStack {
            List {
                if let s = store.snapshot {
                    Section {
                        HStack {
                            Image(systemName: s.running ? "bolt.fill" : "pause.circle").foregroundStyle(s.running ? .green : .secondary)
                            Text(s.running ? "Motore attivo" : "Motore fermo").font(.headline)
                            Spacer()
                            if store.busy { ProgressView() }
                        }
                        Button(s.running ? "Ferma" : "Avvia") { store.send(s.running ? "stop" : "start") }
                            .tint(s.running ? .red : .green)
                            .disabled(!store.reachable)
                    } footer: { Text("Aggiornato \(s.updated.formatted(date: .omitted, time: .shortened))") }

                    if s.entries.isEmpty {
                        Text("Nessuna lezione selezionata").foregroundStyle(.secondary)
                    }
                    ForEach(s.entries) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: e.symbol).foregroundStyle(color(e.state))
                                Text(e.name).font(.headline).lineLimit(1)
                            }
                            Text(df.string(from: e.start)).font(.caption)
                            Text(e.state).font(.caption2).foregroundStyle(color(e.state))
                            if !e.message.isEmpty { Text(e.message).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        }
                    }
                } else {
                    ContentUnavailableView("In attesa dell'iPhone", systemImage: "iphone.and.arrow.forward",
                                           description: Text("Apri Wellness Booking su iPhone."))
                }
            }
            .navigationTitle("Wellness")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send("refresh") } label: { Image(systemName: "arrow.clockwise") }.disabled(!store.reachable)
                }
            }
        }
    }

    private func color(_ state: String) -> Color {
        switch state {
        case "Prenotata": return .green
        case "Lista d'attesa", "Osservazione: piena": return .orange
        case "Prenotazione in corso": return .blue
        case "Errore", "Scaduta": return .red
        default: return .secondary
        }
    }
}
