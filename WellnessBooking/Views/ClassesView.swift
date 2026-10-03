import SwiftUI

/// Scopre tutte le lezioni del centro e permette la selezione multipla.
struct ClassesView: View {
    @EnvironmentObject var engine: BookingEngine
    @State private var filter: String = ""
    @State private var onlyBookable = false
    @State private var selected: Set<String> = []
    @State private var showAddSheet = false
    @State private var recurring = false
    @State private var didInit = false
    @State private var detail: ClassEvent?

    private var filtered: [ClassEvent] {
        engine.classes.filter { e in
            guard e.start > Date() else { return false }
            if onlyBookable && (e.bookingInfo?.bookingAvailable == false) { return false }
            let f = filter.trimmingCharacters(in: .whitespaces)
            return f.isEmpty || e.name.localizedCaseInsensitiveContains(f)
                || (e.assignedTo ?? "").localizedCaseInsensitiveContains(f)
                || (e.room ?? "").localizedCaseInsensitiveContains(f)
        }
    }

    private var grouped: [(Date, [ClassEvent])] {
        let cal = DateParsing.calendar
        let dict = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.start) }
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.start < $1.start }) }
    }

    var body: some View {
        List {
            if let err = engine.lastError, engine.classes.isEmpty {
                Section { Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section {
                EmptyView()
            } footer: {
                if let lr = engine.lastRefresh {
                    Text("\(engine.isServerMode ? (engine.selectedProfile.map { "\($0.label) · \($0.facilityName)" } ?? "Gateway") : engine.settings.facilityName) · \(filtered.count) lezioni nei prossimi \(engine.settings.daysAhead) giorni · aggiornato \(lr.itTime)\(onlyBookable ? " · solo prenotabili online" : "")")
                } else { Text("Scorri verso il basso per aggiornare il calendario.") }
                Text("Tocca una lezione per vedere lo scheduler e attivare la prenotazione automatica; tocca il cerchio per selezionarne più di una.")
            }
            ForEach(grouped, id: \.0) { day, events in
                Section(day.itLongDay) {
                    ForEach(events) { e in
                        ClassRow(event: e, selected: selected.contains(e.key), tracked: engine.isSelected(e)) {
                            guard !engine.isSelected(e) else { return }
                            if selected.contains(e.key) { selected.remove(e.key) } else { selected.insert(e.key) }
                            Haptics.tap(enabled: engine.settings.hapticsEnabled)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { detail = e }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $filter, prompt: "Cerca lezione, istruttore, sala")
        .navigationTitle("Lezioni")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { Task { await engine.refreshClasses() } } label: {
                    if engine.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if engine.isServerMode && engine.profiles.count > 1 && engine.serverUser?.isAdmin == true { ProfileMenu() }
                    Button { onlyBookable.toggle(); Haptics.tap(enabled: engine.settings.hapticsEnabled) } label: {
                        Image(systemName: onlyBookable ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(Text("Solo prenotabili online"))
                    .help(Text("Solo prenotabili online"))
                    Button { showAddSheet = true } label: { Text("Aggiungi \(selected.count)").bold() }
                        .disabled(selected.isEmpty)
                }
            }
        }
        .refreshable { await engine.refreshClasses() }
        .task {
            guard !didInit else { return }
            didInit = true
            filter = engine.settings.nameFilter
            if engine.classes.isEmpty { await engine.refreshClasses() }
        }
        .sheet(item: $detail) { e in ClassDetailView(event: e).environmentObject(engine) }
        .confirmationDialog(selected.count == 1 ? "Aggiungi la lezione alle prenotazioni automatiche" : "Aggiungi \(selected.count) lezioni alle prenotazioni automatiche", isPresented: $showAddSheet, titleVisibility: .visible) {
            Button("Solo queste date") { add(recurring: false) }
            Button("Ogni settimana (stesso giorno e ora)") { add(recurring: true) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("L'app prenoterà all'apertura delle prenotazioni e, se la classe è piena, attiverà l'osservazione per prendere al volo i posti che si liberano.")
        }
    }

    private func add(recurring: Bool) {
        let events = engine.classes.filter { selected.contains($0.key) }
        engine.add(events, recurring: recurring)
        selected.removeAll()
        if !engine.isRunning { engine.start() }
    }
}

struct ClassRow: View {
    let event: ClassEvent
    let selected: Bool
    let tracked: Bool
    var onToggle: () -> Void = {}

    private var statusText: (String, Color) {
        if event.isParticipant == true { return (String(localized: "Prenotata"), .green) }
        if event.isInWaitingList == true { return (String(localized: "In lista d'attesa"), .orange) }
        if event.bookingInfo?.bookingAvailable == false { return (String(localized: "Non prenotabile online"), .secondary) }
        if let o = event.opensOn, o > Date() { return (String(localized: "Apre \(o.itShortDay) alle \(o.itTime)"), .blue) }
        if event.isFull { return ((event.bookingInfo?.bookingHasWaitingList ?? false) ? String(localized: "Piena · lista d'attesa") : String(localized: "Piena"), .red) }
        return (event.placesText, .green)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ClassThumb(url: event.pictureUrl, size: 48)
            Button(action: onToggle) {
                Image(systemName: tracked ? "checkmark.circle.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                    .font(.title2)
                    .foregroundStyle(tracked ? Color.secondary : Color.accentColor)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("\(event.start.itTime) – \(event.end.itTime)").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text(statusText.0).font(.caption).foregroundStyle(statusText.1)
                }
                Text(event.name).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    if let t = event.assignedTo, !t.isEmpty { Label(t.capitalized, systemImage: "person").labelStyle(.titleAndIcon) }
                    if let r = event.room, !r.isEmpty { Label(r, systemImage: "door.left.hand.open") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .opacity(tracked ? 0.6 : 1)
    }
}
