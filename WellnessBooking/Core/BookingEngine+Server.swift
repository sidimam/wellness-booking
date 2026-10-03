import Foundation
import SwiftUI

/// Modalità server: l'app è il telecomando del container wellness-gateway su Unraid.
extension BookingEngine {
    var serverUsername: String { Keychain.get("gw.username") ?? "" }
    var cfAccessClientID: String { Keychain.get("gw.cf-id") ?? "" }
    var cfAccessClientSecret: String { Keychain.get("gw.cf-secret") ?? "" }
    var cfAccessHeaders: [String: String] {
        guard !cfAccessClientID.isEmpty, !cfAccessClientSecret.isEmpty else { return [:] }
        return ["CF-Access-Client-Id": cfAccessClientID, "CF-Access-Client-Secret": cfAccessClientSecret]
    }
    /// Salva (o cancella) il service token Cloudflare Access usato su ogni richiesta al gateway.
    func setCloudflareAccess(clientID: String, clientSecret: String) async {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines), sec = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty || sec.isEmpty { Keychain.delete("gw.cf-id"); Keychain.delete("gw.cf-secret") }
        else { Keychain.set(id, for: "gw.cf-id"); Keychain.set(sec, for: "gw.cf-secret") }
        await gateway.setExtraHeaders(cfAccessHeaders)
        objectWillChange.send()
    }
    var gatewayHostLabel: String {
        let host = URL(string: settings.serverURL)?.host ?? settings.serverURL
        return "\(host) · \(serverUser?.displayName ?? serverUsername)\(serverVersion.isEmpty ? "" : " · v\(serverVersion)")"
    }

    func restoreServer() async {
        await gateway.setExtraHeaders(cfAccessHeaders)
        guard Keychain.get("gw.token") != nil else { return }
        do {
            let me = try await gateway.me()
            serverUser = me.user; serverVersion = me.version; serverPush = me.push
            await refreshServer(force: false)
            startServerPolling()
        } catch {
            if (error as? GatewayClient.Failure)?.status == 401 {
                Keychain.delete("gw.token"); serverUser = nil
                addLog("Sessione del gateway scaduta: accedi di nuovo", .warn)
            } else {
                // offline: mantieni la modalità server con i dati in cache
                if let u = Keychain.get("gw.user"), let d = try? JSONDecoder().decode(GWUser.self, from: Data(u.utf8)) { serverUser = d }
                lastError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func serverLogin(url: String, username: String, password: String) async -> Bool {
        guard let base = URL(string: url.trimmingCharacters(in: .whitespaces)), base.scheme != nil else {
            lastError = String(localized: "Indirizzo del server non valido"); return false
        }
        await gateway.configure(baseURL: base, token: nil, extraHeaders: cfAccessHeaders)
        do {
            let r = try await gateway.login(username: username, password: password, deviceName: UIDevice.current.name)
            settings.serverURL = base.absoluteString
            Keychain.set(r.token, for: "gw.token"); Keychain.set(username, for: "gw.username")
            if let d = try? JSONEncoder().encode(r.user) { Keychain.set(String(decoding: d, as: UTF8.self), for: "gw.user") }
            serverUser = r.user; serverVersion = r.version ?? ""; serverPush = r.push ?? false
            settings.profileChosen = false; settings.selectedProfileID = ""
            lastError = nil
            if isRunning { stop() }
            addLog("Collegata al gateway \(base.host ?? "") come \(r.user.displayName)", .success)
            Notifier.shared.requestAuthorization()
            await refreshServer(force: true)
            startServerPolling()
            return true
        } catch {
            lastError = error.localizedDescription
            addLog("Login al gateway fallito: \(error.localizedDescription)", .error)
            return false
        }
    }

    func serverLogout() async {
        await gateway.logout()
        ["gw.token", "gw.user"].forEach(Keychain.delete)
        serverUser = nil; profiles = []; bookings = []; serverStatus = nil; serverSettings = nil
        serverPollTask?.cancel(); serverPollTask = nil
        items = []
        addLog("Scollegata dal gateway")
    }

    func startServerPolling() {
        serverPollTask?.cancel()
        serverPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.isServerMode else { return }
                await self.refreshServer(force: false, quiet: true)
            }
        }
    }

    /// Scarica profili, lezioni del profilo selezionato, item, prenotazioni e stato.
    /// Verifica che il container risponda (/healthz).
    @discardableResult
    func checkServerHealth() async -> Bool {
        do {
            let h = try await gateway.health()
            serverOnline = true; serverLastSeen = Date()
            if !h.version.isEmpty { serverVersion = h.version }
            return true
        } catch {
            serverOnline = false
            return false
        }
    }

    func refreshServer(force: Bool, quiet: Bool = false) async {
        guard isServerMode, !isRefreshing else { return }
        isRefreshing = true; defer { isRefreshing = false }
        guard await checkServerHealth() else {
            if !quiet { lastError = String(localized: "Gateway non raggiungibile: controlla rete, tunnel o container") }
            return
        }
        do {
            profiles = try await gateway.profiles()
            let mine = profiles.first { $0.userId == serverUser?.id }?.id
            if !settings.profileChosen, let mine, settings.selectedProfileID != mine {
                settings.selectedProfileID = mine          // di default ognuno vede il proprio profilo
            }
            if settings.selectedProfileID.isEmpty || !profiles.contains(where: { $0.id == settings.selectedProfileID }) {
                settings.selectedProfileID = mine ?? profiles.first?.id ?? ""
                settings.profileChosen = false
            }
            let labels = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.label) })
            let gwItems = try await gateway.items(profile: settings.selectedProfileID.isEmpty ? nil : settings.selectedProfileID)
            items = gwItems.map { WatchItem(gw: $0, profileLabel: labels[$0.profileId]) }.sorted { $0.start < $1.start }
            if let p = selectedProfile {
                async let cls = gateway.classes(profile: p.id, refresh: force)
                async let bks = gateway.bookings(profile: p.id, refresh: false)
                classes = try await cls.map(\.event).sorted { $0.start < $1.start }
                bookings = try await bks.map(\.event).sorted { $0.start < $1.start }
            } else { classes = []; bookings = [] }
            serverStatus = try? await gateway.status()
            if serverSettings == nil || force { serverSettings = try? await gateway.settings() }
            lastRefresh = Date(); lastError = nil
        } catch {
            if (error as? GatewayClient.Failure)?.status == 401 { Keychain.delete("gw.token"); serverUser = nil; addLog("Sessione del gateway scaduta", .warn) }
            else if !quiet { lastError = error.localizedDescription }
        }
    }

    func selectProfile(_ id: String) {
        settings.selectedProfileID = id
        settings.profileChosen = (id != profiles.first { $0.userId == serverUser?.id }?.id)
        Task { await refreshServer(force: false) }
    }

    func serverAdd(_ events: [ClassEvent], recurring: Bool) async {
        guard let p = selectedProfile else { lastError = String(localized: "Nessun profilo mywellness sul gateway"); return }
        var n = 0
        for e in events {
            do { _ = try await gateway.addItem(profile: p.id, classId: e.id, partitionDate: e.partitionDate, recurring: recurring); n += 1 }
            catch { lastError = error.localizedDescription; addLog("Aggiunta fallita (\(e.name)): \(error.localizedDescription)", .error) }
        }
        if n > 0 { addLog("Aggiunte \(n) lezioni al gateway per \(p.label)\(recurring ? " (ogni settimana)" : "")", .success); Haptics.success(enabled: settings.hapticsEnabled) }
        await refreshServer(force: false)
    }

    func serverRemove(_ item: WatchItem, rule: Bool) async {
        do { try await gateway.deleteItem(item.id, rule: rule) } catch { lastError = error.localizedDescription }
        await refreshServer(force: false)
    }

    func serverRetry(_ item: WatchItem) async {
        do { _ = try await gateway.retry(item.id) } catch { lastError = error.localizedDescription }
        await refreshServer(force: false)
    }

    func serverUnbook(classId: String, partitionDate: Int) async {
        guard let p = selectedProfile else { return }
        do {
            try await gateway.unbook(profile: p.id, classId: classId, partitionDate: partitionDate)
            addLog("Disdetta inviata al gateway per \(p.label)", .warn)
            Haptics.success(enabled: settings.hapticsEnabled)
        } catch { lastError = error.localizedDescription; addLog("Disdetta fallita: \(error.localizedDescription)", .error) }
        await refreshServer(force: true)
    }

    func serverAddProfile(label: String, username: String, password: String, facilityUrl: String, maxBookings: Int, isPrivate: Bool, mine: Bool = false) async -> Bool {
        do {
            let p = try await gateway.addProfile(label: label, username: username, password: password, facilityUrl: facilityUrl, maxBookings: maxBookings, isPrivate: isPrivate, mine: mine)
            addLog("Profilo \(p.label) aggiunto al gateway", .success)
            settings.selectedProfileID = p.id
            await refreshServer(force: true)
            return true
        } catch { lastError = error.localizedDescription; return false }
    }

    func serverDeleteProfile(_ p: GWProfile) async {
        do { try await gateway.deleteProfile(p.id); addLog("Profilo \(p.label) rimosso dal gateway", .warn) } catch { lastError = error.localizedDescription }
        await refreshServer(force: true)
    }

    func serverRelogin(_ p: GWProfile) async {
        do { _ = try await gateway.relogin(p.id); addLog("Login mywellness rifatto per \(p.label)", .success) } catch { lastError = error.localizedDescription }
        await refreshServer(force: false)
    }

    func saveServerSettings(_ s: GWSettings) async {
        do { serverSettings = try await gateway.putSettings(s); addLog("Impostazioni del gateway salvate", .success) } catch { lastError = error.localizedDescription }
    }

    func loadServerLog() async {
        serverLog = (try? await gateway.log(limit: 300)) ?? []
    }

    func registerAPNS(token: String) async {
        Keychain.set(token, for: "apns.token")
        guard isServerMode else { return }
        do { try await gateway.registerAPNS(token: token); addLog("Token push registrato sul gateway") } catch { addLog("Registrazione push sul gateway fallita: \(error.localizedDescription)", .warn) }
    }

    func serverTestNotification() async -> Int {
        (try? await gateway.testNotification()) ?? 0
    }
}
