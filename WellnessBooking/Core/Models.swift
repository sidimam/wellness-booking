import Foundation

// MARK: - Modelli API mywellness (Technogym)

struct BookingInfo: Codable, Hashable {
    var bookingOpensOn: String?
    var bookingOpensOnMinutesInAdvance: Int?
    var cancellationMinutesInAdvance: Int?
    var bookingCloseMinutesInAdvance: Int?
    var bookingHasWaitingList: Bool?
    var bookingTimeInAdvanceType: String?
    var bookingTimeInAdvanceValue: Int?
    var bookingUserStatus: String?
    var bookingAvailable: Bool?
    var dayInAdvanceStartHour: Int?
    var dayInAdvanceStartMinutes: Int?
}

/// Una lezione (occorrenza) del calendario del centro.
struct ClassEvent: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var startDate: String
    var endDate: String
    var partitionDate: Int
    var room: String?
    var assignedTo: String?
    var maxParticipants: Int?
    var numberOfParticipants: Int?
    var availablePlaces: Int?
    var isParticipant: Bool?
    var isInWaitingList: Bool?
    var waitingListCounter: Int?
    var waitingListPosition: Int?
    var hasBeenDone: Bool?
    var bookingInfo: BookingInfo?
    var facilityId: String?
    var pictureUrl: String?

    /// Chiave univoca dell'occorrenza (stesso id per tutte le ricorrenze, cambia la data).
    var key: String { "\(id)|\(partitionDate)" }
    var start: Date { DateParsing.localDateTime(startDate) ?? .distantPast }
    var end: Date { DateParsing.localDateTime(endDate) ?? start }
    var opensOn: Date? { bookingInfo?.bookingOpensOn.flatMap(DateParsing.offsetDateTime) }
    var isFull: Bool { (availablePlaces ?? 1) <= 0 }
    var placesText: String {
        if let a = availablePlaces, let m = maxParticipants { return "\(a) liberi su \(m)" }
        if let a = availablePlaces { return "\(a) liberi" }
        return ""
    }
}

struct APIError: Codable, Hashable {
    var type: String?
    var errorMessage: String?
    var message: String?
    var field: String?
    var details: String?
    var text: String { errorMessage ?? message ?? details ?? field ?? type ?? "Errore" }
}

struct APIErrorEnvelope: Decodable {
    var errors: [APIError]?
}

struct LoginResponse: Decodable {
    struct UserContext: Decodable {
        var id: FlexibleString
        var firstName: String?
        var lastName: String?
        var email: String?
        var nickName: String?
    }
    struct AccountLocked: Decodable {
        var maxNumberOfAttempts: Int?
        var blockedFor: Int?
    }
    var result: String?
    var token: String?
    var refreshToken: String?
    var userContext: UserContext?
    var accountLockedInfo: AccountLocked?
    var errors: [APIError]?
}

struct BookResponse: Decodable {
    var result: String?
    var message: String?
    var errors: [APIError]?
}

struct FacilityDetail: Decodable {
    var id: String
    var name: String
    var city: String?
    var url: String?
    var logo: String?
}

/// Decodifica un valore che il server può restituire come stringa o numero.
struct FlexibleString: Codable, Hashable {
    var value: String
    init(_ v: String) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(Int(d)) }
        else { throw DecodingError.typeMismatch(String.self, .init(codingPath: decoder.codingPath, debugDescription: "id non riconosciuto")) }
    }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}

// MARK: - Esito prenotazione

enum BookOutcome: Equatable {
    case booked
    case waitingList
    case full                 // PlaceNotAvailable / ToMuchParticipants
    case notOpenYet(String)   // il server rifiuta perché la prenotazione non è ancora aperta
    case tokenInvalid
    case noPermission(String)
    case failed(String)

    var text: String {
        switch self {
        case .booked: return "Prenotata"
        case .waitingList: return "In lista d'attesa"
        case .full: return "Classe piena"
        case .notOpenYet(let m): return "Non ancora aperta: \(m)"
        case .tokenInvalid: return "Sessione scaduta"
        case .noPermission(let m): return "Non autorizzato: \(m)"
        case .failed(let m): return "Errore: \(m)"
        }
    }
}

// MARK: - Date

enum DateParsing {
    static let rome = TimeZone(identifier: "Europe/Rome")!

    private static let local: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rome
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
    private static let offset: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let apiDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rome
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-10-06T17:30:00" (ora locale del centro)
    static func localDateTime(_ s: String) -> Date? {
        local.date(from: String(s.prefix(19)))
    }
    /// "2026-10-03T05:00:00+02:00"
    static func offsetDateTime(_ s: String) -> Date? {
        offset.date(from: s) ?? localDateTime(s)
    }
    static func apiDayString(_ d: Date) -> String { apiDay.string(from: d) }
    static func partitionDate(_ d: Date) -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = rome
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = rome
        cal.locale = Locale(identifier: "it_IT")
        return cal
    }
}

extension Date {
    var itShortDay: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.timeZone = DateParsing.rome
        f.dateFormat = "EEE d MMM"; return f.string(from: self)
    }
    var itLongDay: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.timeZone = DateParsing.rome
        f.dateFormat = "EEEE d MMMM"; return f.string(from: self).capitalized
    }
    var itTime: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.timeZone = DateParsing.rome
        f.dateFormat = "HH:mm"; return f.string(from: self)
    }
    var itDateTime: String { "\(itShortDay) \(itTime)" }
    var itFull: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.timeZone = DateParsing.rome
        f.dateFormat = "EEE d MMM HH:mm:ss"; return f.string(from: self)
    }
}
