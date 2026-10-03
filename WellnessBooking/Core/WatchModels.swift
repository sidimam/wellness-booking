import Foundation

/// Regola di apertura prenotazioni: le lezioni il cui nome contiene `pattern` aprono `daysBefore` giorni prima.
/// "*" = tutte le altre lezioni (regola predefinita); una regola senza nome non si applica. Vince la prima che corrisponde.
struct OpenRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var pattern: String
    var daysBefore: Int
    var hour: Int = 5
    var minute: Int = 0
    var isDefault: Bool { pattern.trimmingCharacters(in: .whitespaces) == "*" }
    var isEmpty: Bool { pattern.trimmingCharacters(in: .whitespaces).isEmpty }
    func matches(_ name: String) -> Bool {
        if isDefault { return true }
        if isEmpty { return false }
        return name.localizedCaseInsensitiveContains(pattern.trimmingCharacters(in: .whitespaces))
    }
}

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
    /// Regole per classe: i nomi li inserisce l'utente (es. "Reformer" → 3 giorni); "*" vale per tutte le altre.
    var openRules: [OpenRule] = [OpenRule(pattern: "", daysBefore: 3), OpenRule(pattern: "*", daysBefore: 7)]

    func rule(for className: String) -> OpenRule {
        openRules.first { !$0.isDefault && !$0.isEmpty && $0.matches(className) }
            ?? openRules.first { $0.isDefault }
            ?? OpenRule(pattern: "*", daysBefore: customDaysBefore, hour: customOpenHour, minute: customOpenMinute)
    }
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

    var keepScreenAwake: Bool = false
    var hapticsEnabled: Bool = true
    var priorityNotifications: Bool = true   // interruptionLevel .timeSensitive
    var iCloudSync: Bool = true
    var appIcon: String = "AppIcon"
    var accent: String = "teal"

    /// Server wellness-gateway (container Unraid): se collegato, è lui a prenotare.
    var serverURL: String = "https://booking.manieridimambro.it"
    var selectedProfileID: String = ""
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
    case cancelled        // disdetta (dal gateway, dall'app o da mywellness)

    var label: String {
        switch self {
        case .pending: return String(localized: "In attesa")
        case .bursting: return String(localized: "Prenotazione in corso")
        case .watching: return String(localized: "Osservazione: piena")
        case .waitingList: return String(localized: "Lista d'attesa")
        case .booked: return String(localized: "Prenotata")
        case .failed: return String(localized: "Errore")
        case .expired: return String(localized: "Scaduta")
        case .cancelled: return String(localized: "Disdetta")
        }
    }
    var isTerminal: Bool {
        switch self { case .booked, .expired, .cancelled: return true; default: return false }
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
        case .cancelled: return "minus.circle"
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
    var pictureUrl: String?
    var profileId: String?
    var profileLabel: String?
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
        start = e.start; end = e.end; room = e.room; trainer = e.assignedTo; pictureUrl = e.pictureUrl
        serverOpensOn = e.opensOn; maxParticipants = e.maxParticipants; availablePlaces = e.availablePlaces
        self.recurring = recurring
    }

    /// Da un item del server wellness-gateway.
    init(gw g: GWItem, profileLabel: String?) {
        id = g.id; classId = g.classId; partitionDate = g.partitionDate; name = g.name
        start = g.start; end = g.end; room = g.room; trainer = g.trainer; pictureUrl = g.pictureUrl
        profileId = g.profileId; self.profileLabel = profileLabel
        serverOpensOn = g.serverOpensOn; serverFireAt = g.fireAt
        maxParticipants = g.maxParticipants; availablePlaces = g.availablePlaces
        recurring = g.recurring; lastMessage = g.lastMessage; lastCheck = g.lastCheck; attempts = g.attempts
        switch g.state {
        case "pending": state = .pending
        case "bursting": state = .bursting
        case "watching": state = .watching
        case "waitingList": state = .waitingList
        case "booked": state = .booked
        case "expired": state = .expired
        case "cancelled": state = .cancelled
        default: state = .failed(g.lastMessage)
        }
    }
    /// Orario calcolato dal server (vince su quello locale quando presente).
    var serverFireAt: Date?

    /// Regola settimanale derivata (nome + giorno + ora) usata per agganciare le occorrenze future.
    var ruleKey: String {
        let cal = DateParsing.calendar
        let c = cal.dateComponents([.weekday, .hour, .minute], from: start)
        return "\(name.lowercased())|\(c.weekday ?? 0)|\(c.hour ?? 0):\(c.minute ?? 0)"
    }

    /// Orario di apertura calcolato con le regole per classe (giorni prima + ora).
    func customFireAt(settings s: AppSettings) -> Date? {
        let r = s.rule(for: name)
        var cal = DateParsing.calendar
        cal.timeZone = DateParsing.rome
        guard let day = cal.date(byAdding: .day, value: -r.daysBefore, to: cal.startOfDay(for: start)) else { return nil }
        return cal.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day)
    }

    /// Quando l'app tenterà la prenotazione: orario del centro (se richiesto e disponibile) altrimenti quello impostato.
    func fireAt(settings s: AppSettings) -> Date? {
        if let f = serverFireAt { return f }
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
