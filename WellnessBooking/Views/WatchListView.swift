import SwiftUI

/// Lezioni seguite: stato dello scheduler e del watchdog.
struct WatchListView: View {
    @EnvironmentObject var engine: BookingEngine
    @State private var confirmCancel: WatchItem?

    private var active: [WatchItem] { engine.items.filter { !$0.state.isTerminal } }
    private var done: [WatchItem] { engine.items.filter { $0.state.isTerminal } }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.isRunning ? "Motore attivo" : "Motore fermo").font(.headline)
                        Text(engine.isLoggedIn ? "Connessa come \(engine.userName ?? engine.username)" : "Non connessa a mywellness")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Prenotazioni attive: \(engine.activeBookingsCount)/\(engine.settings.maxActiveBookings)")
                            .font(.caption).foregroundStyle(engine.bookingLimitReached ? .orange : .secondary)
                    }
                    Spacer()
                    Button(engine.isRunning ? "Ferma" : "Avvia") { engine.isRunning ? engine.stop() : engine.start() }
                        .buttonStyle(.borderedProminent)
                        .tint(engine.isRunning ? .red : .accentColor)
                }
            } footer: {
                Text(engine.settings.keepScreenAwake
                     ? "Con il motore attivo lo schermo resta acceso: tieni l'iPhone in carica e l'app in primo piano all'orario di apertura."
                     : "iOS non esegue l'app in background a orari precisi: tieni l'app aperta all'orario di apertura.")
            }

            if active.isEmpty && done.isEmpty {
                Section { ContentUnavailableView("Nessuna lezione selezionata", systemImage: "calendar.badge.plus",
                                                 description: Text("Vai in Lezioni, seleziona le classi che ti interessano e tocca Aggiungi.")) }
            }
            if !active.isEmpty {
                Section("In corso") { ForEach(active) { item in row(item) } }
            }
            if !done.isEmpty {
                Section("Concluse") { ForEach(done) { item in row(item) } }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Prenotazioni")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await engine.refreshClasses() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .alert("Cancellare la prenotazione?", isPresented: .init(get: { confirmCancel != nil }, set: { if !$0 { confirmCancel = nil } })) {
            Button("Cancella prenotazione", role: .destructive) { if let it = confirmCancel { Task { await engine.cancelBooking(it) } } }
            Button("Annulla", role: .cancel) {}
        } message: { Text(confirmCancel.map { "\($0.name) · \($0.start.itDateTime)" } ?? "") }
    }

    @ViewBuilder
    private func row(_ item: WatchItem) -> some View {
        WatchItemRow(item: item, settings: engine.settings)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { engine.remove(item) } label: { Label("Rimuovi", systemImage: "trash") }
                if item.recurring {
                    Button { engine.removeRule(of: item) } label: { Label("Stop ricorrenza", systemImage: "repeat.circle") }.tint(.orange)
                }
            }
            .swipeActions(edge: .leading) {
                if case .failed = item.state { Button { engine.retry(item) } label: { Label("Riprova", systemImage: "arrow.clockwise") }.tint(.blue) }
                if item.state == .booked, item.start > Date() { Button { confirmCancel = item } label: { Label("Disdici", systemImage: "xmark.circle") }.tint(.red) }
            }
    }
}

struct WatchItemRow: View {
    let item: WatchItem
    let settings: AppSettings

    private var color: Color {
        switch item.state {
        case .booked: return .green
        case .watching, .waitingList: return .orange
        case .bursting: return .blue
        case .failed, .expired: return .red
        case .pending: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.state.symbol).font(.title2).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.name).font(.body.weight(.semibold))
                    if item.recurring { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text(item.state.label).font(.caption.weight(.medium)).foregroundStyle(color)
                }
                Text("\(item.start.itLongDay) · \(item.start.itTime)–\(item.end.itTime)").font(.subheadline)
                if item.state == .pending, let f = item.fireAt(settings: settings) {
                    Text("Prenoto \(f.itShortDay) alle \(f.itTime)").font(.caption).foregroundStyle(.secondary)
                }
                if case .failed(let m) = item.state {
                    Text(m).font(.caption).foregroundStyle(.red)
                } else if !item.lastMessage.isEmpty {
                    Text(item.lastMessage).font(.caption).foregroundStyle(.secondary)
                }
                if let c = item.lastCheck, item.state == .watching || item.state == .waitingList || item.state == .bursting {
                    Text("Ultimo controllo \(c.itTime) · tentativi \(item.attempts)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
