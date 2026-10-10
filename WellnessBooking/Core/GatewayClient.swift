import Foundation

// MARK: - Modelli del server wellness-gateway

struct GWUser: Codable, Equatable {
    var id: String
    var username: String
    var displayName: String
    var isAdmin: Bool
}

struct GWProfile: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var username: String
    var displayName: String?
    var firstName: String?
    var lastName: String?
    var nickName: String?
    var email: String?
    var pictureUrl: String?
    var thumbUrl: String?
    var facilityUrl: String
    var facilityId: String
    var facilityName: String
    var maxBookings: Int
    var userId: String?
    var ownerUserIds: [String]?
    var limits: [GWLimit]?
    var lastLoginAt: Date?
    var lastLoginError: String?
    var activeBookings: Int
    var identity: [String: JSONValue]?   // userContext mywellness completo (senza token/password)
    var card: GWIdentityCard?            // dati mywellness normalizzati dal gateway (per la scheda profilo)
}

/// Dati del profilo mywellness normalizzati dal gateway; l'app li formatta nella lingua dell'utente.
struct GWIdentityCard: Codable, Equatable {
    var fullName: String
    var nickName: String?
    var email: String?
    var gender: String?
    var birthDate: String?          // YYYY-MM-DD
    var culture: String?            // es. it-IT
    var measurementSystem: String?  // Metric / Imperial
    var memberSince: Date?
    var timeZoneWindowsId: String?
    var userId: String?
    var extra: [String: String]?
}

/// Valore JSON generico (per i campi del profilo mywellness che il gateway inoltra così come sono).
enum JSONValue: Codable, Equatable, Hashable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "JSON non riconosciuto") }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
    /// Testo leggibile del valore (vuoto per null/collezioni vuote).
    var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? String(localized: "Sì") : String(localized: "No")
        case .null: return ""
        case .array(let a): return a.map(\.display).filter { !$0.isEmpty }.joined(separator: ", ")
        case .object(let o): return o.keys.sorted().compactMap { k in let v = o[k]!.display; return v.isEmpty ? nil : "\(k): \(v)" }.joined(separator: " · ")
        }
    }
}

struct GWOpenRule: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var pattern: String
    var daysBefore: Int
    var hour: Int
    var minute: Int
    var maxBookings: Int = 0
}

struct GWLimit: Codable, Equatable, Identifiable {
    var id: String { pattern }
    var pattern: String
    var active: Int
    var max: Int
}

struct GWSettings: Codable, Equatable {
    var followServerOpenTime: Bool = true
    var openRules: [GWOpenRule] = []
    var leadMilliseconds: Int = 300
    var burstSeconds: Int = 120
    var pollSeconds: Int = 15
    var nearPollSeconds: Int = 3
    var nearHours: Int = 4
    var daysAhead: Int = 14
    var priorityNotifications: Bool = true
    var custom: Bool? = nil   // true = impostazioni personali diverse dalle predefinite del gateway
}

struct GWItem: Codable, Identifiable, Equatable {
    var id: String
    var profileId: String
    var classId: String
    var partitionDate: Int
    var name: String
    var start: Date
    var end: Date
    var room: String?
    var trainer: String?
    var pictureUrl: String?
    var serverOpensOn: Date?
    var fireAt: Date?
    var recurring: Bool
    var state: String
    var lastMessage: String
    var lastCheck: Date?
    var attempts: Int
    var bookedAt: Date?
    var availablePlaces: Int?
    var maxParticipants: Int?
    var createdBy: String?
}

/// Lezione come restituita dal gateway: campi mywellness + start/end/opensOn/tracked.
struct GWClass: Decodable {
    var event: ClassEvent
    var tracked: GWItem?
    init(from decoder: Decoder) throws {
        event = try ClassEvent(from: decoder)
        let c = try decoder.container(keyedBy: Extra.self)
        tracked = try c.decodeIfPresent(GWItem.self, forKey: .tracked)
    }
    enum Extra: String, CodingKey { case tracked }
}

struct GWLogLine: Codable, Identifiable {
    var id: String { "\(time.timeIntervalSince1970)-\(text.hashValue)" }
    var time: Date
    var level: String
    var profileId: String?
    var text: String
}

struct GWStatus: Codable {
    var version: String
    var startedAt: Date
    var nextWake: Date
    var profiles: Int
    var items: Int
    var activeItems: Int
    var push: Bool
    var publicUrl: String?
}

// MARK: - Client

/// Client REST per wellness-gateway (il container su Unraid). Token per dispositivo nel Keychain.
actor GatewayClient {
    struct Failure: LocalizedError {
        var message: String
        var status: Int
        var errorDescription: String? { message }
    }

    private(set) var baseURL: URL
    private(set) var token: String?
    private(set) var extraHeaders: [String: String] = [:]
    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter(); iso2.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let t = iso.date(from: s) ?? iso2.date(from: s) { return t }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "data non valida: \(s)"))
        }
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForResource = 40
        session = URLSession(configuration: cfg)
    }

    func configure(baseURL: URL, token: String?, extraHeaders: [String: String] = [:]) { self.baseURL = baseURL; self.token = token; self.extraHeaders = extraHeaders }
    func setExtraHeaders(_ h: [String: String]) { extraHeaders = h }
    var isLoggedIn: Bool { token != nil }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, auth: Bool = true, as type: T.Type) async throws -> T {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders where !v.isEmpty { req.setValue(v, forHTTPHeaderField: k) }
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Failure(message: "Risposta non valida", status: 0) }
        guard (200..<300).contains(http.statusCode) else {
            if let ct = http.value(forHTTPHeaderField: "Content-Type"), ct.contains("text/html") {
                let host = http.url?.host ?? ""
                let msg = host.hasSuffix("cloudflareaccess.com") || http.statusCode == 302 || http.statusCode == 403
                    ? String(localized: "Bloccato da Cloudflare Access: attiva \"Connessione tramite Cloudflare Access\" e inserisci Client ID e Client Secret del service token.")
                    : String(localized: "Il server ha risposto con una pagina web (proxy o Cloudflare Access?)")
                throw Failure(message: msg, status: http.statusCode)
            }
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Failure(message: msg, status: http.statusCode)
        }
        if T.self == Empty.self { return Empty() as! T }
        return try decoder.decode(T.self, from: data)
    }
    struct Empty: Decodable {}
    struct ErrorBody: Decodable { var error: String? }

    // MARK: Health
    struct Health: Decodable { var status: String; var version: String }
    /// GET /healthz (senza autenticazione): il container è su?
    func health() async throws -> Health {
        var req = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        req.timeoutInterval = 12
        for (k, v) in extraHeaders where !v.isEmpty { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure(message: String(localized: "Gateway non raggiungibile"), status: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try decoder.decode(Health.self, from: data)
    }

    // MARK: Auth
    struct LoginResponse: Decodable { var token: String; var user: GWUser; var version: String?; var push: Bool? }
    func login(username: String, password: String, deviceName: String) async throws -> LoginResponse {
        struct B: Encodable { let username, password, deviceName: String; let selfOnly: Bool }
        let r = try await request("POST", "/auth/login", body: B(username: username, password: password, deviceName: deviceName, selfOnly: true), auth: false, as: LoginResponse.self)
        token = r.token
        return r
    }
    func logout() async { _ = try? await request("POST", "/auth/logout", as: Empty.self); token = nil }
    struct Me: Decodable { var user: GWUser; var version: String; var push: Bool; var myProfileId: String? }
    func me() async throws -> Me { try await request("GET", "/me", as: Me.self) }
    func registerAPNS(token t: String) async throws { struct B: Encodable { let token: String }; _ = try await request("POST", "/devices/apns", body: B(token: t), as: Empty.self) }
    func testNotification() async throws -> Int { struct R: Decodable { var sent: Int }; return try await request("POST", "/devices/test-notification", as: R.self).sent }
    func status() async throws -> GWStatus { try await request("GET", "/status", as: GWStatus.self) }

    // MARK: Profili
    func profiles() async throws -> [GWProfile] { try await request("GET", "/profiles", as: [GWProfile].self) }
    func addProfile(label: String, username: String, password: String, facilityUrl: String, maxBookings: Int, isPrivate: Bool, mine: Bool) async throws -> GWProfile {
        struct B: Encodable { let label, username, password, facilityUrl: String; let maxBookings: Int; let `private`: Bool; let mine: Bool }
        return try await request("POST", "/profiles", body: B(label: label, username: username, password: password, facilityUrl: facilityUrl, maxBookings: maxBookings, private: isPrivate, mine: mine), as: GWProfile.self)
    }
    /// Altro centro per lo stesso account mywellness: il gateway copia credenziali e proprietario dal profilo sorgente.
    func addCenter(copyFrom profileId: String, facilityUrl: String, maxBookings: Int) async throws -> GWProfile {
        struct B: Encodable { let facilityUrl: String; let maxBookings: Int; let copyFromProfileId: String }
        return try await request("POST", "/profiles", body: B(facilityUrl: facilityUrl, maxBookings: maxBookings, copyFromProfileId: profileId), as: GWProfile.self)
    }
    func deleteProfile(_ id: String) async throws { _ = try await request("DELETE", "/profiles/\(id)", as: Empty.self) }
    func relogin(_ id: String) async throws -> GWProfile { try await request("POST", "/profiles/\(id)/relogin", as: GWProfile.self) }
    func classes(profile: String, refresh: Bool) async throws -> [GWClass] {
        try await request("GET", "/profiles/\(profile)/classes", query: refresh ? ["refresh": "1"] : [:], as: [GWClass].self)
    }
    func bookings(profile: String, refresh: Bool) async throws -> [GWClass] {
        try await request("GET", "/profiles/\(profile)/bookings", query: refresh ? ["refresh": "1"] : [:], as: [GWClass].self)
    }
    func unbook(profile: String, classId: String, partitionDate: Int) async throws {
        struct B: Encodable { let classId: String; let partitionDate: Int }
        _ = try await request("POST", "/profiles/\(profile)/unbook", body: B(classId: classId, partitionDate: partitionDate), as: Empty.self)
    }

    func leaveWaitingList(profile: String, classId: String, partitionDate: Int, removeItem: Bool) async throws {
        struct B: Encodable { let classId: String; let partitionDate: Int; let removeItem: Bool }
        _ = try await request("POST", "/profiles/\(profile)/leave-waiting-list", body: B(classId: classId, partitionDate: partitionDate, removeItem: removeItem), as: Empty.self)
    }

    // MARK: Items
    func items(profile: String? = nil) async throws -> [GWItem] {
        try await request("GET", "/items", query: profile.map { ["profile": $0] } ?? [:], as: [GWItem].self)
    }
    func addItem(profile: String, classId: String, partitionDate: Int, recurring: Bool) async throws -> GWItem {
        struct B: Encodable { let profileId, classId: String; let partitionDate: Int; let recurring: Bool }
        return try await request("POST", "/items", body: B(profileId: profile, classId: classId, partitionDate: partitionDate, recurring: recurring), as: GWItem.self)
    }
    /// Esito della rimozione: il gateway disdice anche su mywellness (prenotazione o lista d'attesa).
    struct RemoveResult: Decodable { var ok: Bool; var removed: Int; var unbooked: [String]; var leftWaitingList: [String]; var errors: [String] }
    func deleteItem(_ id: String, rule: Bool) async throws -> RemoveResult {
        try await request("DELETE", "/items/\(id)", query: rule ? ["rule": "1"] : [:], as: RemoveResult.self)
    }
    func retry(_ id: String) async throws -> GWItem {
        try await request("POST", "/items/\(id)/retry", as: GWItem.self)
    }

    // MARK: Impostazioni e registro
    func settings() async throws -> GWSettings { try await request("GET", "/settings", as: GWSettings.self) }
    func putSettings(_ s: GWSettings) async throws -> GWSettings { try await request("PUT", "/settings", body: s, as: GWSettings.self) }
    /// Torna alle impostazioni predefinite del gateway (elimina quelle personali).
    func resetSettings() async throws -> GWSettings { try await request("DELETE", "/settings", as: GWSettings.self) }
    func log(limit: Int = 200) async throws -> [GWLogLine] { try await request("GET", "/log", query: ["limit": String(limit)], as: [GWLogLine].self) }
}
