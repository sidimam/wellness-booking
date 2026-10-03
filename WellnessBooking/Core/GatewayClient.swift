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
    var facilityUrl: String
    var facilityId: String
    var facilityName: String
    var maxBookings: Int
    var userId: String?
    var ownerUserIds: [String]?
    var lastLoginAt: Date?
    var lastLoginError: String?
    var activeBookings: Int
}

struct GWOpenRule: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var pattern: String
    var daysBefore: Int
    var hour: Int
    var minute: Int
}

struct GWSettings: Codable, Equatable {
    var followServerOpenTime: Bool = true
    var openRules: [GWOpenRule] = []
    var leadMilliseconds: Int = 300
    var burstSeconds: Int = 120
    var pollSeconds: Int = 20
    var daysAhead: Int = 14
    var priorityNotifications: Bool = true
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
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    func configure(baseURL: URL, token: String?) { self.baseURL = baseURL; self.token = token }
    var isLoggedIn: Bool { token != nil }

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, auth: Bool = true, as type: T.Type) async throws -> T {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Failure(message: "Risposta non valida", status: 0) }
        if http.statusCode == 401 { token = nil }
        guard (200..<300).contains(http.statusCode) else {
            if let ct = http.value(forHTTPHeaderField: "Content-Type"), ct.contains("text/html") {
                throw Failure(message: "Il server ha risposto con una pagina web (proxy o Cloudflare Access?)", status: http.statusCode)
            }
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Failure(message: msg, status: http.statusCode)
        }
        if T.self == Empty.self { return Empty() as! T }
        return try decoder.decode(T.self, from: data)
    }
    struct Empty: Decodable {}
    struct ErrorBody: Decodable { var error: String? }

    // MARK: Auth
    struct LoginResponse: Decodable { var token: String; var user: GWUser; var version: String?; var push: Bool? }
    func login(username: String, password: String, deviceName: String) async throws -> LoginResponse {
        struct B: Encodable { let username, password, deviceName: String }
        let r = try await request("POST", "/auth/login", body: B(username: username, password: password, deviceName: deviceName), auth: false, as: LoginResponse.self)
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

    // MARK: Items
    func items(profile: String? = nil) async throws -> [GWItem] {
        try await request("GET", "/items", query: profile.map { ["profile": $0] } ?? [:], as: [GWItem].self)
    }
    func addItem(profile: String, classId: String, partitionDate: Int, recurring: Bool) async throws -> GWItem {
        struct B: Encodable { let profileId, classId: String; let partitionDate: Int; let recurring: Bool }
        return try await request("POST", "/items", body: B(profileId: profile, classId: classId, partitionDate: partitionDate, recurring: recurring), as: GWItem.self)
    }
    func deleteItem(_ id: String, rule: Bool) async throws {
        _ = try await request("DELETE", "/items/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)", query: rule ? ["rule": "1"] : [:], as: Empty.self)
    }
    func retry(_ id: String) async throws -> GWItem {
        try await request("POST", "/items/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/retry", as: GWItem.self)
    }

    // MARK: Impostazioni e registro
    func settings() async throws -> GWSettings { try await request("GET", "/settings", as: GWSettings.self) }
    func putSettings(_ s: GWSettings) async throws -> GWSettings { try await request("PUT", "/settings", body: s, as: GWSettings.self) }
    func log(limit: Int = 200) async throws -> [GWLogLine] { try await request("GET", "/log", query: ["limit": String(limit)], as: [GWLogLine].self) }
}
