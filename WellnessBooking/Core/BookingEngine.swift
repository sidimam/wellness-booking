import Foundation
import SwiftUI
import Combine

/// Motore: scheduler (prenota all'apertura), watchdog (posti liberati), lista d'attesa, ricorrenze.
@MainActor
final class BookingEngine: ObservableObject {
    static let shared = BookingEngine()

    @Published var settings: AppSettings { didSet { if settings != oldValue { Store.saveSettings(settings); applyKeepAwake() } } }
    @Published var items: [WatchItem] { didSet { if items != oldValue { Store.saveItems(items); WatchBridge.shared.push(items: items, running: isRunning) } } }
    @Published var classes: [ClassEvent] = []
    @Published var isRunning = false { didSet { applyKeepAwake(); WatchBridge.shared.push(items: items, running: isRunning) } }
    @Published var isLoggedIn = false
    @Published var userName: String?
    @Published var log: [LogLine] = []
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false
    @Published var lastError: String?

    let api = MyWellnessAPI()
    private var loopTask: Task<Void, Never>?
    private var nextPoll: [String: Date] = [:]
    private var lastFullRefresh: Date = .distantPast

    // MARK: - Credenziali

    var username: String {
        get { Keychain.get("username") ?? "" }
        set { Keychain.set(newValue, for: "username"); objectWillChange.send() }
    }
    var password: String {
        get { Keychain.get("password") ?? "" }
        set { Keychain.set(newValue, for: "password"); objectWillChange.send() }
    }
    var hasCredentials: Bool { !username.isEmpty && !password.isEmpty }

    private init() {
        settings = Store.loadSettings()
        items = Store.loadItems()
        log = Store.loadLog()
        Task { await restoreSession() }
        Store.onCloudChange = { [weak self] in Task { @MainActor in self?.mergeFromCloud() } }
    }

    // MARK: - Log

    func addLog(_ text: String, _ level: LogLine.Level = .info) {
        log.insert(LogLine(level: level, text: text), at: 0)
        if log.count > 400 { log.removeLast(log.count - 400) }
        Store.saveLog(log)
    }
    func clearLog() { log = []; Store.saveLog(log) }

    // MARK: - Sessione

    private func restoreSession() async {
        if let t = Keychain.get("token"), let u = Keychain.get("userId") {
            await api.restore(token: t, userId: u, name: Keychain.get("userName"))
            isLoggedIn = true
            userName = Keychain.get("userName")
        }
    }

    @discardableResult
    func login() async -> Bool {
        guard hasCredentials else { lastError = "Inserisci email e password nelle Impostazioni."; return false }
        do {
            try await api.login(username: username, password: password)
            isLoggedIn = true
            userName = await api.userDisplayName
            if let t = await api.token { Keychain.set(t, for: "token") }
            if let u = await api.userId { Keychain.set(u, for: "userId") }
            if let n = userName { Keychain.set(n, for: "userName") }
            lastError = nil
            addLog("Login riuscito come \(userName ?? username)", .success)
            return true
        } catch {
            isLoggedIn = false
            lastError = error.localizedDescription
            addLog("Login fallito: \(error.localizedDescription)", .error)
            return false
        }
    }

    func logout() async {
        await api.logout()
        ["token", "userId", "userName"].forEach(Keychain.delete)
        isLoggedIn = false; userName = nil
        addLog("Disconnesso")
    }

    // MARK: - Centro

    func resolveFacility() async {
        do {
            let f = try await api.facilityDetail(url: settings.facilityUrl.trimmingCharacters(in: .whitespaces).lowercased())
            settings.facilityId = f.id
            settings.facilityName = f.name
            addLog("Centro: \(f.name) (\(f.city ?? ""))", .success)
            lastError = nil
        } catch { lastError = error.localizedDescription; addLog("Centro non trovato: \(error.localizedDescription)", .error) }
    }

    // MARK: - Calendario

    func refreshClasses() async {
        guard !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        let from = Date()
        let to = DateParsing.calendar.date(byAdding: .day, value: settings.daysAhead, to: from) ?? from
        do {
            let list = try await api.searchClasses(facilityId: settings.facilityId, from: from, to: to)
            classes = list.sorted { $0.start < $1.start }
            lastRefresh = Date()
            lastFullRefresh = Date()
            lastError = nil
            syncItems(with: classes)
            attachRecurring()
        } catch {
            lastError = error.localizedDescription
            addLog("Aggiornamento calendario fallito: \(error.localizedDescription)", .warn)
            if (error as? MyWellnessAPI.APIFailure)?.status == 401 { _ = await login() }
        }
    }

    /// Aggiorna gli item con i dati freschi del calendario (posti, apertura, stato partecipante).
    private func syncItems(with events: [ClassEvent]) {
        let byKey = Dictionary(uniqueKeysWithValues: events.map { ($0.key, $0) })
        for i in items.indices {
            guard let e = byKey[items[i].id] else { continue }
            items[i].availablePlaces = e.availablePlaces
            items[i].maxParticipants = e.maxParticipants
            items[i].serverOpensOn = e.opensOn ?? items[i].serverOpensOn
            if e.isParticipant == true, items[i].state != .booked {
                markBooked(index: i, note: "Risulti già iscritta/o sul calendario")
            } else if e.isInWaitingList == true, items[i].state == .pending || items[i].state == .watching {
                items[i].state = .waitingList
            }
        }
    }

    /// Per gli item ricorrenti aggancia le occorrenze future non ancora seguite.
    private func attachRecurring() {
        let rules = Set(items.filter(\.recurring).map(\.ruleKey))
        guard !rules.isEmpty else { return }
        let known = Set(items.map(\.id))
        for e in classes where e.start > Date() && !known.contains(e.key) {
            let probe = WatchItem(event: e, recurring: true)
            if rules.contains(probe.ruleKey) {
                var it = probe
                if e.isParticipant == true { it.state = .booked }
                items.append(it)
                addLog("Ricorrenza: aggiunta \(e.name) \(e.start.itDateTime)")
            }
        }
        items.sort { $0.start < $1.start }
    }

    // MARK: - Selezione

    func isSelected(_ e: ClassEvent) -> Bool { items.contains { $0.id == e.key } }

    func add(_ events: [ClassEvent], recurring: Bool) {
        var added = 0
        for e in events where !isSelected(e) {
            var it = WatchItem(event: e, recurring: recurring)
            if e.isParticipant == true { it.state = .booked; it.lastMessage = "Già prenotata" }
            else if e.isInWaitingList == true { it.state = .waitingList }
            items.append(it); added += 1
        }
        items.sort { $0.start < $1.start }
        if added > 0 {
            addLog("Aggiunte \(added) lezioni\(recurring ? " (ogni settimana)" : "")", .success)
            if recurring { attachRecurring() }
            Notifier.shared.scheduleReminders(for: items, settings: settings)
        }
    }

    func remove(_ item: WatchItem) {
        items.removeAll { $0.id == item.id }
        nextPoll[item.id] = nil
        Notifier.shared.scheduleReminders(for: items, settings: settings)
    }

    func removeRule(of item: WatchItem) {
        let k = item.ruleKey
        items.removeAll { $0.ruleKey == k && !$0.state.isTerminal }
        for i in items.indices where items[i].ruleKey == k { items[i].recurring = false }
    }

    func retry(_ item: WatchItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].state = .pending; items[i].lastMessage = ""; items[i].attempts = 0
        nextPoll[item.id] = nil
    }

    func cancelBooking(_ item: WatchItem) async {
        if !isLoggedIn { guard await login() else { return } }
        do {
            if try await api.unbook(classId: item.classId, partitionDate: item.partitionDate) {
                addLog("Prenotazione cancellata: \(item.name) \(item.start.itDateTime)", .warn)
                remove(item)
            } else { addLog("Cancellazione non riuscita per \(item.name)", .error) }
        } catch { addLog("Cancellazione fallita: \(error.localizedDescription)", .error) }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        addLog("Motore avviato", .success)
        Notifier.shared.requestAuthorization()
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel(); loopTask = nil
        addLog("Motore fermato", .warn)
    }

    private func applyKeepAwake() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = isRunning && settings.keepScreenAwake
        #endif
    }

    // MARK: - Loop principale

    private func runLoop() async {
        let hasToken = await api.token != nil
        if !isLoggedIn || !hasToken { _ = await login() }
        if classes.isEmpty || Date().timeIntervalSince(lastFullRefresh) > 600 { await refreshClasses() }
        Notifier.shared.scheduleReminders(for: items, settings: settings)

        while !Task.isCancelled && isRunning {
            let now = Date()
            if now.timeIntervalSince(lastFullRefresh) > 600 { await refreshClasses() }

            var wake: Date = now.addingTimeInterval(5)
            for idx in items.indices {
                guard idx < items.count else { break }
                let item = items[idx]
                if item.state.isTerminal { continue }
                if case .failed = item.state { continue }

                // scadenza: chiusura prenotazioni (default 5 minuti prima)
                if now >= item.start.addingTimeInterval(-5 * 60) {
                    items[idx].state = .expired
                    items[idx].lastMessage = "Prenotazioni chiuse"
                    addLog("Scaduta: \(item.name) \(item.start.itDateTime)", .warn)
                    continue
                }

                switch item.state {
                case .pending:
                    guard let fire = item.fireAt(settings: settings) else {
                        items[idx].lastMessage = "Orario di apertura sconosciuto"; continue
                    }
                    let target = fire.addingTimeInterval(-Double(settings.leadMilliseconds) / 1000)
                    if now >= target {
                        items[idx].state = .bursting
                        await attempt(index: idx, reason: "apertura prenotazioni")
                    } else {
                        wake = min(wake, target)
                    }
                case .bursting:
                    let fire = item.fireAt(settings: settings) ?? now
                    if now <= fire.addingTimeInterval(Double(settings.burstSeconds)) {
                        await attempt(index: idx, reason: "ritentativo")
                        wake = min(wake, Date().addingTimeInterval(1.5))
                    } else {
                        items[idx].state = .watching
                        items[idx].lastMessage = "Finestra di apertura conclusa, passo al watchdog"
                        addLog("\(item.name) \(item.start.itDateTime): watchdog attivo", .info)
                    }
                case .watching, .waitingList:
                    let due = nextPoll[item.id] ?? now
                    if now >= due {
                        await watchdogCheck(index: idx)
                        let interval = pollInterval(for: items[idx])
                        nextPoll[item.id] = Date().addingTimeInterval(interval)
                        wake = min(wake, nextPoll[item.id]!)
                    } else { wake = min(wake, due) }
                default: break
                }
            }

            // Dormi fino al prossimo evento, con precisione al millisecondo vicino all'apertura.
            let delay = max(0.05, wake.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(min(delay, 5) * 1_000_000_000))
        }
    }

    /// Intervallo del watchdog: più stretto vicino alla scadenza di cancellazione (2 h prima).
    private func pollInterval(for item: WatchItem) -> TimeInterval {
        let base = Double(max(5, settings.pollSeconds))
        let toCancelDeadline = item.start.addingTimeInterval(-120 * 60).timeIntervalSinceNow
        if toCancelDeadline > 0 && toCancelDeadline < 45 * 60 { return max(5, base / 3) }   // ultimi 45 min utili
        if item.start.timeIntervalSinceNow < 6 * 3600 { return max(5, base / 2) }
        return base
    }

    // MARK: - Tentativo di prenotazione

    private func attempt(index idx: Int, reason: String) async {
        guard idx < items.count else { return }
        let item = items[idx]
        items[idx].attempts += 1
        items[idx].lastCheck = Date()
        do {
            var outcome = try await api.book(classId: item.classId, partitionDate: item.partitionDate)
            if outcome == .tokenInvalid {
                if await login() { outcome = try await api.book(classId: item.classId, partitionDate: item.partitionDate) }
            }
            handle(outcome, index: idx, reason: reason)
        } catch {
            items[idx].lastMessage = "Rete: \(error.localizedDescription)"
            addLog("\(item.name): errore di rete (\(error.localizedDescription))", .warn)
        }
    }

    private func handle(_ outcome: BookOutcome, index idx: Int, reason: String) {
        guard idx < items.count else { return }
        let item = items[idx]
        items[idx].lastMessage = outcome.text
        switch outcome {
        case .booked:
            markBooked(index: idx, note: "Prenotata (\(reason))")
        case .waitingList:
            if item.state != .waitingList {
                items[idx].state = .waitingList
                addLog("\(item.name) \(item.start.itDateTime): classe piena, sei in lista d'attesa. Watchdog attivo.", .warn)
                Notifier.shared.notify(title: "Lista d'attesa", body: "\(item.name) \(item.start.itDateTime) è piena: watchdog attivo, prenoto appena si libera un posto.", priority: false)
            }
        case .full:
            if item.state != .watching && item.state != .waitingList {
                items[idx].state = .watching
                addLog("\(item.name) \(item.start.itDateTime): piena, watchdog attivo", .warn)
            }
        case .notOpenYet(let m):
            items[idx].lastMessage = "Non ancora aperta (\(m))"
        case .tokenInvalid:
            items[idx].lastMessage = "Login non riuscito"
        case .noPermission(let m):
            items[idx].state = .failed(m)
            addLog("\(item.name): non autorizzato (\(m))", .error)
            Notifier.shared.notify(title: "Prenotazione rifiutata", body: "\(item.name): \(m)", priority: true)
        case .failed(let m):
            if item.state == .bursting { items[idx].lastMessage = "Tentativo fallito: \(m)" }
            else { addLog("\(item.name): \(m)", .warn) }
        }
    }

    private func markBooked(index idx: Int, note: String) {
        let item = items[idx]
        items[idx].state = .booked
        items[idx].lastMessage = note
        nextPoll[item.id] = nil
        addLog("✅ \(item.name) \(item.start.itDateTime): \(note)", .success)
        Notifier.shared.notify(title: "Prenotata ✅", body: "\(item.name) · \(item.start.itLongDay) alle \(item.start.itTime)", priority: true)
        Haptics.success(enabled: settings.hapticsEnabled)
    }

    // MARK: - Watchdog

    private func watchdogCheck(index idx: Int) async {
        guard idx < items.count else { return }
        let item = items[idx]
        items[idx].lastCheck = Date()
        do {
            let day = item.start
            let events = try await api.searchClasses(facilityId: settings.facilityId, from: day, to: day)
            guard let e = events.first(where: { $0.key == item.id }) else {
                items[idx].lastMessage = "Lezione non più in calendario"; return
            }
            items[idx].availablePlaces = e.availablePlaces
            items[idx].maxParticipants = e.maxParticipants
            if e.isParticipant == true { markBooked(index: idx, note: "Posto confermato dal calendario"); return }
            if (e.availablePlaces ?? 0) > 0 {
                addLog("🔔 Posto libero per \(item.name) \(item.start.itDateTime): prenoto subito", .success)
                Notifier.shared.notify(title: "Posto libero!", body: "\(item.name) \(item.start.itDateTime): sto prenotando…", priority: true)
                await attempt(index: idx, reason: "posto liberato")
                if items.indices.contains(idx), items[idx].state != .booked {
                    // qualcun altro è stato più veloce: resta in watchdog stretto
                    nextPoll[item.id] = Date().addingTimeInterval(3)
                }
            } else {
                items[idx].lastMessage = "Piena (\(e.numberOfParticipants ?? 0)/\(e.maxParticipants ?? 0))" + (e.isInWaitingList == true ? " · in lista d'attesa" : "")
            }
        } catch {
            items[idx].lastMessage = "Rete: \(error.localizedDescription)"
            if (error as? MyWellnessAPI.APIFailure)?.status == 401 { _ = await login() }
        }
    }

    // MARK: - Background (best effort)

    /// Eseguito da BGAppRefresh quando iOS concede tempo in background: un giro di watchdog/scheduler.
    func backgroundCheck() async {
        guard !items.isEmpty else { return }
        let hasToken = await api.token != nil
        if !isLoggedIn || !hasToken { _ = await login() }
        let now = Date()
        for idx in items.indices {
            guard idx < items.count else { break }
            let it = items[idx]
            switch it.state {
            case .pending:
                if let f = it.fireAt(settings: settings), now >= f { await attempt(index: idx, reason: "background") }
            case .bursting:
                await attempt(index: idx, reason: "background")
            case .watching, .waitingList:
                await watchdogCheck(index: idx)
            default: break
            }
        }
        addLog("Controllo in background eseguito")
    }

    // MARK: - iCloud

    private func mergeFromCloud() {
        let cloudSettings = Store.loadSettings()
        let cloudItems = Store.loadItems()
        if cloudSettings != settings { settings = cloudSettings }
        if cloudItems != items {
            var merged = items
            for c in cloudItems where !merged.contains(where: { $0.id == c.id }) { merged.append(c) }
            items = merged.sorted { $0.start < $1.start }
            addLog("Sincronizzato da iCloud")
        }
    }
}
