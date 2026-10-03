import SwiftUI

/// Lezioni seguite + prenotazioni attive (gateway e mywellness), con disdetta.
struct WatchListView: View {
    @EnvironmentObject var engine: BookingEngine
    @State private var confirmCancel: (name: String, classId: String, partitionDate: Int)?
    @State private var confirmLeave: WatchItem?

    private var active: [WatchItem] { engine.items.filter { !$0.state.isTerminal } }
    private func bookedByGateway(_ e: ClassEvent) -> Bool {
        let pid = engine.selectedProfile?.id
        return engine.items.contains { $0.classId == e.id && $0.partitionDate == e.partitionDate && $0.profileId == pid }
    }
    private var done: [WatchItem] { engine.items.filter { $0.state.isTerminal } }

    var body: some View {
        List {
            header
            if engine.isServerMode {
                Section {
                    if engine.bookings.isEmpty {
                        Text("Nessuna prenotazione attiva").foregroundStyle(.secondary)
                    }
                    ForEach(engine.bookings) { e in
                        HStack(spacing: 12) {
                            ClassThumb(url: e.pictureUrl, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.name).font(.body.weight(.semibold))
                                Text("\(e.start.itLongDay) · \(e.start.itTime)–\(e.end.itTime)").font(.subheadline)
                                Text(bookedByGateway(e) ? "Prenotata dal gateway" : "Prenotata da mywellness (app o web)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { confirmCancel = (e.name, e.id, e.partitionDate) } label: { Label("Disdici", systemImage: "xmark.circle") }
                        }
                    }
                } header: { Text("Prenotate su mywellness · \(engine.selectedProfile?.label ?? "")") } footer: {
                    Text("Tutte le prenotazioni attive del profilo, fatte dal gateway o dall'app/sito Technogym. Scorri a sinistra per disdire.")
                }
            }
            if active.isEmpty && done.isEmpty {
                Section { ContentUnavailableView("Nessuna lezione selezionata", systemImage: "calendar.badge.plus",
                                                 description: Text("Vai in Lezioni, seleziona le classi che ti interessano e tocca Aggiungi.")) }
            }
            if !active.isEmpty { Section("In corso") { ForEach(active) { item in row(item) } } }
            if !done.isEmpty { Section("Concluse") { ForEach(done) { item in row(item) } } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Prenotazioni")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if engine.isServerMode && engine.profiles.count > 1 { ProfileMenu() }
                    Button { Task { await engine.refreshClasses() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .refreshable { await engine.refreshClasses() }
        .alert("Disdire la prenotazione?", isPresented: .init(get: { confirmCancel != nil }, set: { if !$0 { confirmCancel = nil } })) {
            Button("Disdici su mywellness", role: .destructive) {
                if let c = confirmCancel {
                    Task {
                        if engine.isServerMode { await engine.serverUnbook(classId: c.classId, partitionDate: c.partitionDate) }
                        else if let it = engine.items.first(where: { $0.classId == c.classId && $0.partitionDate == c.partitionDate }) { await engine.cancelBooking(it) }
                    }
                }
            }
            Button("Annulla", role: .cancel) {}
        } message: { Text(confirmCancel?.name ?? "") }
        .alert("Uscire dalla lista d'attesa?", isPresented: .init(get: { confirmLeave != nil }, set: { if !$0 { confirmLeave = nil } })) {
            Button("Esci dalla lista d'attesa", role: .destructive) { if let it = confirmLeave { Task { await engine.serverLeaveWaitingList(it) } } }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Il gateway ti toglie dalla lista d'attesa su mywellness e smette di seguire la lezione. \"Rimuovi\" invece lascia la lista d'attesa com'è e toglie solo il monitoraggio.") }
    }

    @ViewBuilder private var header: some View {
        if engine.isServerMode {
            Section {
                HStack(spacing: 10) {
                    Circle().fill(engine.serverOnline == true ? Color.green : (engine.serverOnline == false ? Color.red : Color.secondary)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.serverOnline == false ? "Gateway non raggiungibile" : "Gateway online\(engine.serverVersion.isEmpty ? "" : " · v\(engine.serverVersion)")")
                            .font(.subheadline.weight(.semibold))
                        if let p = engine.selectedProfile {
                            Text("\(p.label): prenotazioni attive \(p.activeBookings)/\(p.maxBookings)")
                                .font(.caption).foregroundStyle(p.activeBookings >= p.maxBookings ? .orange : .secondary)
                            if p.userId != engine.serverUser?.id {
                                Text("Stai vedendo il profilo di \(p.label) (scelto dal menu profilo).").font(.caption2).foregroundStyle(.orange)
                            }
                        } else {
                            Text("Nessun profilo mywellness: collega il tuo account in Altro → Profili mywellness.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if let d = engine.serverLastSeen { Text(d.itTime).font(.caption2).foregroundStyle(.tertiary) }
                }
                if let e = engine.lastError { Label(e, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
            }
        } else {
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
                     : "In background iOS risveglia l'app solo quando decide lui: per la massima precisione all'apertura tieni l'app in primo piano, altrimenti riceverai un promemoria 3 minuti prima. Collega il gateway di casa (Altro → Server) per prenotare 24 ore su 24.")
            }
        }
    }

    @ViewBuilder
    private func row(_ item: WatchItem) -> some View {
        WatchItemRow(item: item, settings: engine.settings, showProfile: engine.isServerMode && engine.profiles.count > 1)
            .swipeActions(edge: .trailing) {
                if item.state == .waitingList && engine.isServerMode {
                    Button(role: .destructive) { confirmLeave = item } label: { Label("Esci dalla lista d'attesa", systemImage: "person.2.slash") }
                }
                Button { engine.remove(item) } label: { Label("Rimuovi", systemImage: "trash") }.tint(.gray)
                if item.recurring {
                    Button { engine.removeRule(of: item) } label: { Label("Stop ricorrenza", systemImage: "repeat.circle") }.tint(.orange)
                }
            }
            .swipeActions(edge: .leading) {
                if case .failed = item.state { Button { engine.retry(item) } label: { Label("Riprova", systemImage: "arrow.clockwise") }.tint(.blue) }
                if item.state == .booked, item.start > Date() {
                    Button { confirmCancel = (item.name, item.classId, item.partitionDate) } label: { Label("Disdici", systemImage: "xmark.circle") }.tint(.red)
                }
            }
    }
}

struct WatchItemRow: View {
    let item: WatchItem
    let settings: AppSettings
    var showProfile = false

    private var color: Color {
        switch item.state {
        case .booked: return .green
        case .watching, .waitingList: return .orange
        case .bursting: return .blue
        case .failed, .expired, .cancelled: return .red
        case .pending: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ClassThumb(url: item.pictureUrl, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: item.state.symbol).foregroundStyle(color)
                    Text(item.name).font(.body.weight(.semibold))
                    if item.recurring { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text(item.state.label).font(.caption.weight(.medium)).foregroundStyle(color)
                }
                Text("\(item.start.itLongDay) · \(item.start.itTime)–\(item.end.itTime)").font(.subheadline)
                if showProfile, let p = item.profileLabel { Text(p).font(.caption).foregroundStyle(Color.accentColor) }
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
