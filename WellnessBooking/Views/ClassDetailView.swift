import SwiftUI

/// Scheda lezione: dettagli, scheduler (quando l'app prenoterà) e sottoscrizione automatica.
struct ClassDetailView: View {
    @EnvironmentObject var engine: BookingEngine
    @Environment(\.dismiss) private var dismiss
    let event: ClassEvent

    private var tracked: WatchItem? { engine.items.first { $0.id == event.key } }
    private var probe: WatchItem { WatchItem(event: event, recurring: false) }
    private var fireAt: Date? { probe.fireAt(settings: engine.settings) }
    private var weekday: String {
        let f = DateFormatter(); f.locale = AppLanguage.current.locale; f.dateFormat = "EEEE"; return f.string(from: event.start)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let u = event.pictureUrl, let url = URL(string: u) {
                    Section {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                            .frame(height: 160).clipped().listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    LabeledContent("Lezione", value: event.name)
                    LabeledContent("Quando", value: "\(event.start.itLongDay) · \(event.start.itTime)–\(event.end.itTime)")
                    if let t = event.assignedTo, !t.isEmpty { LabeledContent("Istruttore", value: t.capitalized) }
                    if let r = event.room, !r.isEmpty { LabeledContent("Sala", value: r) }
                    LabeledContent("Posti") {
                        Text(event.isFull ? "Piena (\(event.numberOfParticipants ?? 0)/\(event.maxParticipants ?? 0))" : event.placesText)
                            .foregroundStyle(event.isFull ? .red : .green)
                    }
                    if event.isParticipant == true { Label("Sei già prenotata/o", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    if event.isInWaitingList == true { Label("Sei in lista d'attesa", systemImage: "person.2.wave.2").foregroundStyle(.orange) }
                }

                Section {
                    if let o = event.opensOn {
                        LabeledContent("Apertura comunicata dal centro", value: "\(o.itShortDay) \(o.itTime)")
                    }
                    if let f = fireAt {
                        LabeledContent("L'app prenoterà") {
                            Text(f > Date() ? "\(f.itShortDay) alle \(f.itTime)" : "subito (apertura già avvenuta)")
                                .foregroundStyle(Color.accentColor).bold()
                        }
                    }
                    LabeledContent("Regola") {
                        let r = engine.settings.rule(for: event.name)
                        Text("\(r.isDefault ? "*" : r.pattern) · \(r.daysBefore) gg · \(String(format: "%02d:%02d", r.hour, r.minute))")
                    }
                    if !engine.isServerMode {
                        Toggle(isOn: .init(get: { !engine.settings.useCustomOpenTime }, set: { engine.settings.useCustomOpenTime = !$0 })) {
                            Text("Segui l'orario del centro")
                        }
                    } else if let p = engine.selectedProfile {
                        LabeledContent("Profilo", value: p.label)
                    }
                    if event.isFull || event.isParticipant != true {
                        Label(event.isFull ? "Classe piena: entro in lista d'attesa e l'osservazione prenota appena si libera un posto."
                                           : "Se all'apertura la classe si riempie, l'osservazione resta attiva sui posti che si liberano.",
                              systemImage: "eye").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Scheduler") } footer: {
                    Text(engine.isServerMode ? "Prenota il gateway di casa, sempre acceso: regole e anticipo in Altro → Scheduler." : "Ora e anticipo in millisecondi si regolano in Altro → Scheduler.")
                }

                Section {
                    if let t = tracked {
                        HStack {
                            Image(systemName: t.state.symbol)
                            Text(t.state.label).bold()
                            if t.recurring { Image(systemName: "repeat") }
                            Spacer()
                        }
                        if !t.lastMessage.isEmpty { Text(t.lastMessage).font(.footnote).foregroundStyle(.secondary) }
                        Button(role: .destructive) { engine.remove(t); dismiss() } label: { Label("Rimuovi dalla prenotazione automatica", systemImage: "trash") }
                    } else {
                        Button { subscribe(recurring: false) } label: { Label("Prenota automaticamente questa lezione", systemImage: "calendar.badge.checkmark") }
                        Button { subscribe(recurring: true) } label: { Label("Prenota ogni \(weekday) alle \(event.start.itTime)", systemImage: "repeat") }
                    }
                } header: { Text("Prenotazione automatica") }
            }
            .navigationTitle(event.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Chiudi") { dismiss() } } }
        }
    }

    private func subscribe(recurring: Bool) {
        engine.add([event], recurring: recurring)
        if !engine.isRunning { engine.start() }
        Haptics.success(enabled: engine.settings.hapticsEnabled)
        dismiss()
    }
}
