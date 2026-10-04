import SwiftUI
import UserNotifications

/// Tab "Altro": account, centro, scheduler, watchdog, aspetto, notifiche, log, info.
struct MoreView: View {
    @EnvironmentObject var engine: BookingEngine
    @AppStorage("themeMode") private var themeMode = ThemeMode.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("walkthroughDone") private var walkthroughDone = false
    @State private var email = ""
    @State private var password = ""
    @State private var testing = false
    @State private var facilityUrl = ""
    @State private var notifStatus = "…"
    @State private var openTime = Date()
    @State private var loaded = false
    @State private var gwURL = ""
    @State private var gwUser = ""
    @State private var gwPass = ""
    @State private var gwBusy = false

    var body: some View {
        Form {
            Section {
                if engine.isServerMode {
                    HStack(spacing: 12) {
                        ProfileAvatar(profile: engine.profiles.first { $0.userId == engine.serverUser?.id }, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.serverUser?.displayName ?? "").font(.body.weight(.semibold))
                            if let p = engine.profiles.first(where: { $0.userId == engine.serverUser?.id }) {
                                Text(p.email ?? p.username).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(engine.gatewayHostLabel).font(.caption2).foregroundStyle(.green)
                        }
                    }
                    LabeledContent {
                        HStack(spacing: 6) {
                            Circle().fill(engine.serverOnline == true ? Color.green : (engine.serverOnline == false ? Color.red : Color.secondary)).frame(width: 9, height: 9)
                            Text(engine.serverOnline == true ? "Online" : (engine.serverOnline == false ? "Non raggiungibile" : "…"))
                                .foregroundStyle(engine.serverOnline == false ? .red : .secondary)
                        }
                    } label: { Label("Container", systemImage: "shippingbox") }
                    if let p = engine.selectedProfile {
                        LabeledContent { Text("\(p.activeBookings)/\(p.maxBookings)" + (p.limits ?? []).map { " · \($0.pattern) \($0.active)/\($0.max)" }.joined()).foregroundStyle(.secondary) } label: { Label("Prenotazioni attive", systemImage: "checkmark.circle") }
                    }
                    if let d = engine.serverLastSeen { LabeledContent { Text(d.itTime).foregroundStyle(.secondary) } label: { Label("Ultimo contatto", systemImage: "clock") } }
                    Button { Task { await engine.refreshServer(force: true) } } label: { Label("Verifica ora", systemImage: "arrow.clockwise") }
                    if let s = engine.serverStatus {
                        LabeledContent { Text("avviato \(s.startedAt.itDateTime) · prossimo controllo \(s.nextWake.itTime)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } label: { Label("Motore", systemImage: "bolt") }
                    }
                    NavigationLink { ServerProfilesView() } label: { Label(engine.serverUser?.isAdmin == true ? "Profili mywellness (\(engine.profiles.count))" : "Il mio profilo mywellness", systemImage: engine.serverUser?.isAdmin == true ? "person.2" : "person") }
                    NavigationLink { ServerSettingsView() } label: { Label("Scheduler e osservazione", systemImage: "clock.badge") }
                    NavigationLink { CloudflareAccessView() } label: {
                        LabeledContent { Text(engine.cfAccessClientID.isEmpty ? "No" : "Attivo").foregroundStyle(.secondary) } label: { Label("Cloudflare Access", systemImage: "cloud.fill") }
                    }
                    if let s = engine.serverStatus {
                        LabeledContent { Text(s.push ? "attivo" : "non configurato").foregroundStyle(s.push ? .green : .orange) } label: { Label("Push dal gateway", systemImage: "bell.and.waves.left.and.right") }
                    }
                    Button(role: .destructive) { Task { await engine.serverLogout() } } label: { Label("Scollega", systemImage: "power") }
                } else {
                    ServerLoginFields(url: $gwURL, username: $gwUser, password: $gwPass, busy: $gwBusy)
                    if let e = engine.lastError, !gwUser.isEmpty { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) }
                }
            } header: { Text("Server di casa (wellness-gateway)") } footer: {
                Text(engine.isServerMode
                     ? "Il container su Unraid prenota e osserva 24 ore su 24 per tutti i profili e manda le notifiche push. Da qui scegli le lezioni e disdici."
                     : "Collega il container wellness-gateway del tuo NAS: prenota lui, sempre acceso, anche con l'iPhone spento. Senza server l'app lavora da sola ma solo in primo piano.")
            }

            if !engine.isServerMode {
            Section {
                TextField("Email mywellness", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                PasswordField(title: "Password", text: $password)
                Button {
                    engine.username = email.trimmingCharacters(in: .whitespaces)
                    engine.password = password
                    testing = true
                    Task { await engine.login(); await engine.refreshClasses(); testing = false }
                } label: {
                    HStack { Label("Salva e verifica login", systemImage: "person.badge.key"); Spacer(); if testing { ProgressView() } }
                }
                .disabled(email.isEmpty || password.isEmpty || testing)
                if engine.isLoggedIn {
                    LabeledContent { Text(engine.userName ?? "").foregroundStyle(.green) } label: { Label("Connessa", systemImage: "checkmark.circle") }
                    Button(role: .destructive) { Task { await engine.logout() } } label: { Label("Esci", systemImage: "power") }
                } else if let e = engine.lastError {
                    Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote)
                }
            } header: { Text("Account Technogym mywellness") } footer: {
                Text("Le stesse credenziali della web app mywellness: tocca il campo e usa l'icona chiave della tastiera per prenderle dalle Password di iCloud. Sono salvate nel Keychain di questo iPhone.")
            }

            Section {
                HStack {
                    TextField("URL centro (es. wellnesstown)", text: $facilityUrl).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Cerca") { engine.settings.facilityUrl = facilityUrl; Task { await engine.resolveFacility(); await engine.refreshClasses() } }
                        .buttonStyle(.bordered).disabled(facilityUrl.isEmpty)
                }
                LabeledContent { Text(engine.settings.facilityName) } label: { Label("Centro", systemImage: "building.2") }
                TextField("Filtro lezioni predefinito", text: $engine.settings.nameFilter)
                Stepper("Giorni di calendario: \(engine.settings.daysAhead)", value: $engine.settings.daysAhead, in: 3...30)
                Stepper("Massimo prenotazioni attive: \(engine.settings.maxActiveBookings)", value: $engine.settings.maxActiveBookings, in: 1...30)
            } header: { Text("Centro") } footer: {
                Text("L'URL è la parte finale dell'indirizzo del widget: widgets.mywellness.com/facility/‹url›/schedule/…\nIl limite di prenotazioni attive è quello imposto dal centro (Wellness Town: 5). Il conteggio include anche le prenotazioni fatte direttamente su mywellness (lette dal calendario con il tuo login): l'app non supera il limite e riprende appena una lezione è passata o viene disdetta.")
            }

            Section {
                Toggle(isOn: .init(get: { !engine.settings.useCustomOpenTime }, set: { engine.settings.useCustomOpenTime = !$0 })) {
                    Label("Segui l'orario del centro", systemImage: "building.2.crop.circle")
                }
                ForEach($engine.settings.openRules) { $rule in
                    OpenRuleRow(rule: $rule)
                }
                .onDelete { idx in engine.settings.openRules.remove(atOffsets: idx) }
                Button {
                    engine.settings.openRules.insert(OpenRule(pattern: "", daysBefore: 3), at: max(0, engine.settings.openRules.count - 1))
                } label: { Label("Aggiungi regola", systemImage: "plus.circle") }
                Stepper("Anticipo: \(engine.settings.leadMilliseconds) ms", value: $engine.settings.leadMilliseconds, in: 0...3000, step: 100)
                Stepper("Insisti per \(engine.settings.burstSeconds) s dopo l'apertura", value: $engine.settings.burstSeconds, in: 10...600, step: 10)
            } header: { Text("Scheduler") } footer: {
                Text(engine.settings.useCustomOpenTime
                     ? "L'app usa le regole qui sopra: scrivi tu il testo da cercare nel nome della lezione (es. Reformer); la prima regola che corrisponde decide giorni e ora di apertura, la regola * vale per tutte le altre. Le regole senza nome sono ignorate."
                     : "Con \"Segui l'orario del centro\" attivo l'app usa l'apertura comunicata da mywellness per ogni lezione. Le regole qui sotto servono quando il centro non la comunica o se disattivi l'opzione: scrivi tu il testo da cercare nel nome della lezione (es. Reformer → 3 giorni); la prima regola che corrisponde decide giorni e ora, * vale per tutte le altre.")
            }

            Section {
                Stepper("Controlla ogni \(engine.settings.pollSeconds) s", value: $engine.settings.pollSeconds, in: 5...300, step: 5)
                Toggle(isOn: $engine.settings.keepScreenAwake) { Label("Tieni lo schermo acceso (in primo piano)", systemImage: "sun.max") }
            } header: { Text("Osservazione") } footer: {
                Text("Quando una classe è piena l'app resta in lista d'attesa e controlla i posti liberi a questo intervallo (più fitto nelle ultime ore utili). Appena si libera un posto prenota e ti avvisa.\nIn background iOS concede risvegli solo a sua discrezione (Background App Refresh): l'app li chiede vicino all'apertura e ai controlli, ma non sono garantiti al secondo. Lo schermo acceso serve solo se vuoi la precisione massima tenendo l'app in primo piano.")
            }
            } // !isServerMode

            Section {
                Toggle(isOn: $engine.settings.priorityNotifications) { Label("Notifiche prioritarie", systemImage: "bell.badge") }
                Toggle(isOn: $engine.settings.hapticsEnabled) { Label("Vibrazione", systemImage: "iphone.radiowaves.left.and.right") }
                LabeledContent { Text(notifStatus).foregroundStyle(.secondary) } label: { Label("Permesso notifiche", systemImage: "bell") }
                Button { openNotificationSettings() } label: { Label("Impostazioni notifiche di iOS", systemImage: "gear") }
                Button {
                    if engine.isServerMode { Task { _ = await engine.serverTestNotification() } }
                    else { Notifier.shared.notify(title: String(localized: "Notifica di prova"), body: String(localized: "Così ti avviso quando prenoto o si libera un posto."), priority: engine.settings.priorityNotifications) }
                } label: {
                    Label(engine.isServerMode ? "Invia notifica di prova dal gateway" : "Invia notifica di prova", systemImage: "paperplane")
                }
            } header: { Text("Notifiche") } footer: {
                Text("Le notifiche prioritarie (Time Sensitive) arrivano anche con Focus o Non disturbare attivi e compaiono su Apple Watch.")
            }

            Section {
                Picker(selection: $themeMode) { ForEach(ThemeMode.allCases) { Text($0.label).tag($0.rawValue) } } label: { Label("Aspetto", systemImage: "circle.lefthalf.filled") }
                Picker(selection: $appLanguage) { ForEach(AppLanguage.allCases) { Text($0.label).tag($0.rawValue) } } label: { Label("Lingua", systemImage: "globe") }
                    .onChange(of: appLanguage) { _, new in AppLanguage(rawValue: new)?.apply() }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Colore app", systemImage: "paintpalette")
                    IconColorPicker(selection: $engine.settings.accent)
                }
                Toggle(isOn: $engine.settings.iCloudSync) { Label("Sincronizza con iCloud", systemImage: "icloud") }
            } header: { Text("Impostazioni app") } footer: {
                Text("Il colore cambia anche l'icona. La lingua si applica subito ai testi e completamente al riavvio dell'app. iCloud sincronizza impostazioni e lezioni selezionate tra i tuoi dispositivi (non la password).")
            }

            Section("Supporto") {
                NavigationLink { LogView() } label: { Label("Registro attività", systemImage: "doc.text.magnifyingglass") }
                Button { walkthroughDone = false } label: { Label("Rivedi la presentazione", systemImage: "sparkles") }
            }

            Section("Informazioni app") {
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")
                LabeledContent("Autore", value: "Simone Di Mambro")
                Link(destination: URL(string: "https://widgets.mywellness.com/facility/\(engine.settings.facilityUrl)/schedule/\(engine.settings.facilityUrl)")!) {
                    Label("Apri il calendario mywellness", systemImage: "arrow.up.right.square")
                }
            }
        }
        .navigationTitle("Altro")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            email = engine.username; password = engine.password
            facilityUrl = engine.settings.facilityUrl
            gwURL = UserDefaults.standard.string(forKey: "serverURLOverride") ?? engine.settings.serverURL; gwUser = engine.serverUsername
            openTime = Calendar.current.date(bySettingHour: engine.settings.customOpenHour, minute: engine.settings.customOpenMinute, second: 0, of: Date()) ?? Date()
            refreshNotifStatus()
        }
    }

    private func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let t: String
            switch s.authorizationStatus {
            case .authorized: t = s.timeSensitiveSetting == .enabled ? String(localized: "Attive (prioritarie ok)") : String(localized: "Attive")
            case .provisional: t = String(localized: "Riepilogo")
            case .denied: t = String(localized: "Disattivate")
            case .notDetermined: t = String(localized: "Non richieste")
            default: t = "—"
            }
            DispatchQueue.main.async { notifStatus = t }
        }
    }

    private func openNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async {
                if s.authorizationStatus == .notDetermined { Notifier.shared.requestAuthorization(); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { refreshNotifStatus() } }
                else if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }
}

/// Riga di una regola di apertura: testo da cercare nel nome, giorni prima, ora.
struct OpenRuleRow: View {
    @Binding var rule: OpenRule
    @State private var time = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: rule.isDefault ? "asterisk.circle" : "textformat").foregroundStyle(.secondary)
                TextField("Nome lezione (es. Reformer)", text: $rule.pattern)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(rule.isDefault)
            }
            HStack {
                Stepper("Giorni prima: \(rule.daysBefore)", value: $rule.daysBefore, in: 0...30)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                    .onChange(of: time) { _, d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        rule.hour = c.hour ?? 5; rule.minute = c.minute ?? 0
                    }
            }
        }
        .onAppear { time = Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date() }
    }
}

struct LogView: View {
    @EnvironmentObject var engine: BookingEngine
    var body: some View {
        if engine.isServerMode { ServerLogView() } else { localLog }
    }
    private var localLog: some View {
        List(engine.log) { l in
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(color(l.level)).frame(width: 8, height: 8).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.text).font(.subheadline)
                    Text(l.date.itFull).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if engine.log.isEmpty { ContentUnavailableView("Nessuna attività", systemImage: "doc.text") } }
        .navigationTitle("Registro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: engine.log.map { "\($0.date.itFull) [\($0.level.rawValue)] \($0.text)" }.joined(separator: "\n")) { Label("Esporta", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { engine.clearLog() } label: { Label("Svuota", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
    private func color(_ l: LogLine.Level) -> Color {
        switch l { case .info: .secondary; case .success: .green; case .warn: .orange; case .error: .red }
    }
}

struct ServerLogView: View {
    @EnvironmentObject var engine: BookingEngine
    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: engine.profiles.map { ($0.id, $0.label) })
        List(engine.serverLog) { l in
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(color(l.level)).frame(width: 8, height: 8).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    if let p = l.profileId, let n = names[p] { Text(n).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Text(l.text).font(.subheadline)
                    Text(l.time.itFull).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .overlay { if engine.serverLog.isEmpty { ContentUnavailableView("Nessuna attività", systemImage: "doc.text") } }
        .navigationTitle("Registro del gateway")
        .navigationBarTitleDisplayMode(.inline)
        .task { await engine.loadServerLog() }
        .refreshable { await engine.loadServerLog() }
    }
    private func color(_ l: String) -> Color {
        switch l { case "success": .green; case "warn": .orange; case "error": .red; default: .secondary }
    }
}
