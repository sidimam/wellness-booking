import AppIntents

/// App Intents: Siri, Comandi rapidi, Spotlight e Action Button.
struct StartEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "Avvia prenotazioni automatiche"
    static var description = IntentDescription("Avvia il motore di Wellness Booking (scheduler e osservazione).")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        BookingEngine.shared.start()
        return .result(dialog: "Motore avviato.")
    }
}

struct StopEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "Ferma prenotazioni automatiche"
    static var description = IntentDescription("Ferma il motore di Wellness Booking.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        BookingEngine.shared.stop()
        return .result(dialog: "Motore fermato.")
    }
}

struct RefreshClassesIntent: AppIntent {
    static var title: LocalizedStringResource = "Aggiorna calendario lezioni"
    static var description = IntentDescription("Ricarica il calendario del centro e controlla le lezioni seguite.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        await BookingEngine.shared.refreshClasses()
        await BookingEngine.shared.backgroundCheck()
        return .result(dialog: "Calendario aggiornato.")
    }
}

struct BookingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Stato prenotazioni"
    static var description = IntentDescription("Riassume le lezioni seguite da Wellness Booking.")
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let e = BookingEngine.shared
        let active = e.items.filter { !$0.state.isTerminal && $0.start > Date() }
        let booked = e.items.filter { $0.state == .booked && $0.start > Date() }
        if active.isEmpty && booked.isEmpty { return .result(dialog: "Nessuna lezione seguita.") }
        let lines = (booked + active).sorted { $0.start < $1.start }.prefix(5).map { "\($0.name) \($0.start.itDateTime): \($0.state.label)" }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: ". ")))
    }
}

struct WellnessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartEngineIntent(), phrases: ["Avvia ${applicationName}", "Avvia le prenotazioni con ${applicationName}"],
                    shortTitle: "Avvia", systemImageName: "play.fill")
        AppShortcut(intent: StopEngineIntent(), phrases: ["Ferma ${applicationName}"],
                    shortTitle: "Ferma", systemImageName: "stop.fill")
        AppShortcut(intent: BookingStatusIntent(), phrases: ["Stato prenotazioni ${applicationName}", "Come vanno le prenotazioni su ${applicationName}"],
                    shortTitle: "Stato", systemImageName: "checkmark.circle")
        AppShortcut(intent: RefreshClassesIntent(), phrases: ["Aggiorna ${applicationName}"],
                    shortTitle: "Aggiorna", systemImageName: "arrow.clockwise")
    }
}
