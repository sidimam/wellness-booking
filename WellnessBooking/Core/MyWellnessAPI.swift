import Foundation

/// Client per le API pubbliche usate dalla web app mywellness (widgets.mywellness.com).
/// Endpoint ricavati dal bundle JS del widget di prenotazione.
actor MyWellnessAPI {
    static let appId = "EC1D38D7-D359-48D0-A60C-D8C0B8FB9DF9"   // enduser web app
    static let appName = "enduserweb"
    static let appVersion = "1.0.0"
    static let culture = "it-IT"

    static let coreURL = URL(string: "https://core.mywellness.com")!
    static let calendarURL = URL(string: "https://calendar.mywellness.com")!

    struct APIFailure: LocalizedError {
        var message: String
        var status: Int
        var errorDescription: String? { message }
    }

    private(set) var token: String?
    private(set) var userId: String?
    private(set) var userDisplayName: String?

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) WellnessBooking/1.0"]
        session = URLSession(configuration: cfg)
    }

    var isLoggedIn: Bool { token != nil && userId != nil }

    func restore(token: String?, userId: String?, name: String?) {
        self.token = token; self.userId = userId; self.userDisplayName = name
    }

    func logout() { token = nil; userId = nil; userDisplayName = nil }

    // MARK: - Richieste

    private func makeRequest(_ base: URL, path: String, query: [String: String] = [:], method: String, body: (any Encodable)? = nil, auth: Bool) throws -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "_c", value: Self.culture))
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(Self.appId, forHTTPHeaderField: "X-MWAPPS-APPID")
        req.setValue(Self.appName, forHTTPHeaderField: "X-MWAPPS-CLIENT")
        req.setValue("\(Self.appVersion),\(Self.appName)", forHTTPHeaderField: "X-MWAPPS-CLIENTVERSION")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("https://widgets.mywellness.com", forHTTPHeaderField: "Origin")
        req.setValue("https://widgets.mywellness.com/", forHTTPHeaderField: "Referer")
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIFailure(message: "Risposta non valida", status: 0) }
        return (data, http)
    }

    private func errorsIn(_ data: Data) -> [APIError]? {
        (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.errors
    }

    // MARK: - Login

    @discardableResult
    func login(username: String, password: String) async throws -> LoginResponse {
        struct Body: Encodable { let username: String; let password: String; let keepMeLoggedIn: Bool }
        let req = try makeRequest(Self.coreURL, path: "/v2/enduser/authentication/login",
                                  method: "POST", body: Body(username: username, password: password, keepMeLoggedIn: true), auth: false)
        let (data, http) = try await send(req)
        let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data)

        if let errs = decoded?.errors ?? errorsIn(data), !errs.isEmpty {
            throw APIFailure(message: errs.map(\.text).joined(separator: "; "), status: http.statusCode)
        }
        guard (200..<300).contains(http.statusCode), let decoded else {
            if http.statusCode == 401, let r = decoded?.result, r.lowercased() == "mfarequired" {
                throw APIFailure(message: "L'account richiede un codice MFA: disattivalo oppure usa un account senza verifica in due passaggi.", status: 401)
            }
            throw APIFailure(message: "Login rifiutato (HTTP \(http.statusCode))", status: http.statusCode)
        }
        var tok = decoded.token
        if tok == nil, let h = http.value(forHTTPHeaderField: "Authorization") {
            let parts = h.split(separator: " "); if parts.count > 1 { tok = String(parts[1]) }
        }
        guard let user = decoded.userContext, let tok else {
            if let locked = decoded.accountLockedInfo, let m = locked.blockedFor {
                throw APIFailure(message: "Account bloccato per \(m) minuti (troppi tentativi).", status: http.statusCode)
            }
            throw APIFailure(message: decoded.result.map { "Login fallito: \($0)" } ?? "Credenziali non valide", status: http.statusCode)
        }
        token = tok
        userId = user.id.value
        let name = [user.firstName, user.lastName].compactMap { $0 }.joined(separator: " ")
        userDisplayName = name.isEmpty ? (user.nickName ?? username) : name
        return decoded
    }

    // MARK: - Centro

    func facilityDetail(url facilityUrl: String) async throws -> FacilityDetail {
        let req = try makeRequest(Self.coreURL, path: "/v2/enduser/facility/detail",
                                  query: ["facilityUrl": facilityUrl], method: "GET", auth: isLoggedIn)
        let (data, http) = try await send(req)
        guard (200..<300).contains(http.statusCode) else {
            throw APIFailure(message: "Centro '\(facilityUrl)' non trovato (HTTP \(http.statusCode))", status: http.statusCode)
        }
        return try JSONDecoder().decode(FacilityDetail.self, from: data)
    }

    // MARK: - Calendario

    /// Elenco lezioni tra due date (incluse). Senza login è pubblico; con login popola isParticipant.
    func searchClasses(facilityId: String, from: Date, to: Date) async throws -> [ClassEvent] {
        let req = try makeRequest(Self.calendarURL, path: "/v2/enduser/class/Search",
                                  query: ["eventTypes": "Class",
                                          "facilityId": facilityId,
                                          "fromDate": DateParsing.apiDayString(from),
                                          "toDate": DateParsing.apiDayString(to)],
                                  method: "GET", auth: isLoggedIn)
        let (data, http) = try await send(req)
        if http.statusCode == 401 { token = nil; throw APIFailure(message: "Sessione scaduta", status: 401) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIFailure(message: "Errore calendario (HTTP \(http.statusCode))", status: http.statusCode)
        }
        if let arr = try? JSONDecoder().decode([ClassEvent].self, from: data) { return arr }
        struct Wrapped: Decodable { var data: [ClassEvent]? }
        if let w = try? JSONDecoder().decode(Wrapped.self, from: data), let d = w.data { return d }
        if let errs = errorsIn(data) { throw APIFailure(message: errs.map(\.text).joined(separator: "; "), status: http.statusCode) }
        throw APIFailure(message: "Formato calendario non riconosciuto", status: http.statusCode)
    }

    // MARK: - Prenotazione

    func book(classId: String, partitionDate: Int) async throws -> BookOutcome {
        guard let userId, token != nil else { return .tokenInvalid }
        struct Body: Encodable { let partitionDate: Int; let userId: String; let classId: String; let station: String? }
        let req = try makeRequest(Self.calendarURL, path: "/v2/enduser/class/Book", method: "POST",
                                  body: Body(partitionDate: partitionDate, userId: userId, classId: classId, station: nil), auth: true)
        let (data, http) = try await send(req)
        let decoded = try? JSONDecoder().decode(BookResponse.self, from: data)

        if http.statusCode == 401 { token = nil; return .tokenInvalid }
        if let errs = decoded?.errors ?? errorsIn(data), let first = errs.first {
            let field = (first.field ?? first.details ?? "")
            if errs.contains(where: { $0.type == "Security" && ($0.field == "TokenNotValid" || $0.details == "TokenNotValid") }) {
                token = nil; return .tokenInvalid
            }
            if field.contains("NoPermissionsForUserException") { return .noPermission(first.text) }
            let msg = errs.map(\.text).joined(separator: "; ")
            if msg.localizedCaseInsensitiveContains("not open") || msg.localizedCaseInsensitiveContains("non ancora")
                || msg.localizedCaseInsensitiveContains("aperta") || field.localizedCaseInsensitiveContains("NotOpen")
                || field.localizedCaseInsensitiveContains("TooEarly") || field.localizedCaseInsensitiveContains("InAdvance") {
                return .notOpenYet(msg)
            }
            return .failed(msg)
        }
        guard (200..<300).contains(http.statusCode), let decoded else {
            return .failed("HTTP \(http.statusCode)")
        }
        switch decoded.result ?? "" {
        case "Booked": return .booked
        case "UserAddedToWaitingList": return .waitingList
        case "PlaceNotAvailable", "ToMuchParticipants": return .full
        case "Failed": return .failed(decoded.message ?? "Failed")
        default: return .failed("\(decoded.result ?? "?"): \(decoded.message ?? "")")
        }
    }

    /// Cancella una prenotazione (stesso schema di Book).
    func unbook(classId: String, partitionDate: Int) async throws -> Bool {
        guard let userId, token != nil else { return false }
        struct Body: Encodable { let partitionDate: Int; let userId: String; let classId: String }
        let req = try makeRequest(Self.calendarURL, path: "/v2/enduser/class/Unbook", method: "POST",
                                  body: Body(partitionDate: partitionDate, userId: userId, classId: classId), auth: true)
        let (data, http) = try await send(req)
        guard (200..<300).contains(http.statusCode) else { return false }
        if let errs = errorsIn(data), !errs.isEmpty { return false }
        struct R: Decodable { var result: String? }
        let r = try? JSONDecoder().decode(R.self, from: data)
        return (r?.result ?? "").lowercased().contains("unbooked") || r?.result == nil
    }
}

/// Wrapper per codificare un Encodable generico.
struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeFn = { try value.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}
