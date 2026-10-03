import Foundation

/// Impostazioni dell'app (persistite in UserDefaults + iCloud KVS).
struct AppSettings: Codable, Equatable {
    var facilityUrl: String = "wellnesstown"
    var facilityId: String = "3ecba6bf-19b8-476b-953a-d4a7a5ec0faa"
    var facilityName: String = "Wellness Town"
    var nameFilter: String = ""
    var daysAhead: Int = 14

    /// Scheduler: se false usa l'orario di apertura comunicato dal server (bookingOpensOn).
    var useCustomOpenTime: Bool = false
    var customOpenHour: Int = 5
    var customOpenMinute: Int = 0
    var customDaysBefore: Int = 3
    /// Anticipo in millisecondi rispetto all'orario di apertura (per compensare la latenza).
    var leadMilliseconds: Int = 300
    /// Per quanti secondi insistere (ogni ~1.5 s) subito dopo l'apertura.
    var burstSeconds: Int = 120

    /// Watchdog: ogni quanti secondi controllare se si è liberato un posto.
    var pollSeconds: Int = 30
    /// Se la classe è piena, entrare comunque in lista d'attesa (oltre al watchdog).
    var joinWaitingList: Bool = true

    /// Limite di prenotazioni attive imposto dal centro (Wellness Town: 5).
    var maxActiveBookings: Int = 5

    var keepScreenAwake: Bool = true
    var hapticsEnabled: Bool = true
    var priorityNotifications: Bool = true   // interruptionLevel .timeSensitive
    var iCloudSync: Bool = true
    var appIcon: String = "AppIcon"
    var accent: String = "teal"
}

/// Stato di una lezione seguita dall'app.
enum WatchState: Codable, Equatable {
    case pending          // in attesa dell'orario di apertura
    case bursting         // orario raggiunto, tentativi ravvicinati in corso
    case watching         // classe piena: osservazione attiva
    case waitingList      // in lista d'attesa (+ watchdog)
    case booked
    case failed(String)
    case expired

    var label: String {
        switch self {
        case .pending: return "In attesa"
        case .bursting: return "Prenotazione in corso"
        case .watching: return "Osservazione: piena"
        case .waitingList: return "Lista d'attesa"
        case .booked: return "Prenotata"
        case .failed: return "Errore"
        case .expired: return "Scaduta"
        }
    }
    var isTerminal: Bool {
        switch self { case .booked, .expired: return true; default: return false }
    }
    var symbol: String {
        switch self {
        case .pending: return "clock"
        case .bursting: return "bolt.fill"
        case .watching: return "eye.fill"
        case .waitingList: return "person.2.wave.2.fill"
        case .booked: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .expired: return "xmark.circle"
        }
    }
}

/// Una lezione che l'utente ha chiesto all'app di prenotare.
struct WatchItem: Codable, Identifiable, Equatable {
    var id: String            // == ClassEvent.key
    var classId: String
    var partitionDate: Int
    var name: String
    var start: Date
    var end: Date
    var room: String?
    var trainer: String?
    var serverOpensOn: Date?
    var maxParticipants: Int?
    var availablePlaces: Int?
    var recurring: Bool = false
    var state: WatchState = .pending
    var lastMessage: String = ""
    var lastCheck: Date?
    var attempts: Int = 0
    var createdAt: Date = Date()

    init(event e: ClassEvent, recurring: Bool) {
        id = e.key; classId = e.id; partitionDate = e.partitionDate; name = e.name
        start = e.start; end = e.end; room = e.room; trainer = e.assignedTo
        serverOpensOn = e.opensOn; maxParticipants = e.maxParticipants; availablePlaces = e.availablePlaces
        self.recurring = recurring
    }

    /// Regola settimanale derivata (nome + giorno + ora) usata per agganciare le occorrenze future.
    var ruleKey: String {
        let cal = DateParsing.calendar
        let c = cal.dateComponents([.weekday, .hour, .minute], from: start)
        return "\(name.lowercased())|\(c.weekday ?? 0)|\(c.hour ?? 0):\(c.minute ?? 0)"
    }

    /// Orario di apertura calcolato con le impostazioni (giorni prima + ora).
    func customFireAt(settings s: AppSettings) -> Date? {
        var cal = DateParsing.calendar
        cal.timeZone = DateParsing.rome
        guard let day = cal.date(byAdding: .day, value: -s.customDaysBefore, to: cal.startOfDay(for: start)) else { return nil }
        return cal.date(bySettingHour: s.customOpenHour, minute: s.customOpenMinute, second: 0, of: day)
    }

    /// Quando l'app tenterà la prenotazione: orario del centro (se richiesto e disponibile) altrimenti quello impostato.
    func fireAt(settings s: AppSettings) -> Date? {
        if !s.useCustomOpenTime, let server = serverOpensOn { return server }
        return customFireAt(settings: s)
    }
}

struct LogLine: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var level: Level = .info
    var text: String
    enum Level: String, Codable { case info, success, warn, error }
}
