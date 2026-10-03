import SwiftUI

/// Sezione "Server" (gateway di casa) per la schermata Altro e il walkthrough.
struct ServerLoginFields: View {
    @EnvironmentObject var engine: BookingEngine
    @Binding var url: String
    @Binding var username: String
    @Binding var password: String
    @Binding var busy: Bool
    var onSuccess: () -> Void = {}
    @State private var useAccess = false
    @State private var cfID = ""
    @State private var cfSecret = ""

    var body: some View {
        TextField("https://booking.manieridimambro.it", text: $url)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.URL)
        TextField("Nome utente del gateway", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
        PasswordField(title: "Password del gateway", text: $password)
        Toggle(isOn: $useAccess.animation()) { Label("Connessione tramite Cloudflare Access", systemImage: "cloud.fill") }
        if useAccess {
            TextField("CF-Access-Client-Id", text: $cfID).textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
            PasswordField(title: "CF-Access-Client-Secret", text: $cfSecret, contentType: .oneTimeCode, monospaced: true)
            Text("Service token dell'applicazione Access che protegge l'indirizzo del gateway (Zero Trust → Access → Service Auth). Inviato come intestazione su ogni richiesta.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Button {
            busy = true
            Task {
                await engine.setCloudflareAccess(clientID: useAccess ? cfID : "", clientSecret: useAccess ? cfSecret : "")
                if await engine.serverLogin(url: url, username: username, password: password) { onSuccess() }
                busy = false
            }
        } label: {
            HStack { Label("Collega al gateway", systemImage: "server.rack"); Spacer(); if busy { ProgressView() } }
        }
        .disabled(url.isEmpty || username.isEmpty || password.isEmpty || busy || (useAccess && (cfID.isEmpty || cfSecret.isEmpty)))
        .onAppear { cfID = engine.cfAccessClientID; cfSecret = engine.cfAccessClientSecret; useAccess = !cfID.isEmpty }
    }
}

/// Modifica del service token Cloudflare Access a gateway già collegato.
struct CloudflareAccessView: View {
    @EnvironmentObject var engine: BookingEngine
    @Environment(\.dismiss) private var dismiss
    @State private var cfID = ""
    @State private var cfSecret = ""
    var body: some View {
        Form {
            Section {
                TextField("CF-Access-Client-Id", text: $cfID).textInputAutocapitalization(.never).autocorrectionDisabled().font(.footnote.monospaced())
                PasswordField(title: "CF-Access-Client-Secret", text: $cfSecret, contentType: .oneTimeCode, monospaced: true)
            } header: { Text("Service token") } footer: {
                Text("Se l'indirizzo del gateway è protetto da Cloudflare Access, l'app invia queste intestazioni su ogni richiesta (come Unraid Drive). Lascia vuoto per disattivare. I valori restano nel Keychain di questo iPhone.")
            }
            Section {
                Button("Salva") { Task { await engine.setCloudflareAccess(clientID: cfID, clientSecret: cfSecret); await engine.refreshServer(force: true); dismiss() } }
                if !engine.cfAccessClientID.isEmpty {
                    Button("Rimuovi service token", role: .destructive) { Task { await engine.setCloudflareAccess(clientID: "", clientSecret: ""); dismiss() } }
                }
            }
        }
        .navigationTitle("Cloudflare Access")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { cfID = engine.cfAccessClientID; cfSecret = engine.cfAccessClientSecret }
    }
}

/// Gestione profili mywellness sul gateway.
struct ServerProfilesView: View {
    @EnvironmentObject var engine: BookingEngine
    @State private var showAdd = false
    @State private var label = ""
    @State private var email = ""
    @State private var password = ""
    @State private var facility = "wellnesstown"
    @State private var maxBookings = 5
    @State private var isPrivate = false
    @State private var mine = false
    @State private var busy = false
    @State private var confirmDelete: GWProfile?

    var body: some View {
        List {
            if !engine.profiles.contains(where: { $0.userId == engine.serverUser?.id }) {
                Section {
                    Button { mine = true; label = engine.serverUser?.displayName ?? ""; showAdd = true } label: {
                        Label("Collega il mio account mywellness", systemImage: "person.crop.circle.badge.plus")
                    }
                } footer: {
                    Text("Non hai ancora un profilo mywellness tuo: finché manca, l'app mostra il primo profilo della famiglia.")
                }
            }
            Section {
                ForEach(engine.profiles) { p in
                    HStack(spacing: 12) {
                    ProfileAvatar(profile: p, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.label).font(.body.weight(.semibold))
                            if p.userId == engine.serverUser?.id { Text("io").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1).background(Color.accentColor.opacity(0.15)).clipShape(Capsule()) }
                            if p.ownerUserIds?.isEmpty == false { Image(systemName: "lock").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text("\(p.activeBookings)/\(p.maxBookings)").font(.caption.monospacedDigit()).foregroundStyle(p.activeBookings >= p.maxBookings ? .orange : .secondary)
                        }
                        if let n = p.displayName, !n.isEmpty { Text(n + (p.nickName.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary) }
                        Text("\(p.username) · \(p.facilityName)").font(.caption).foregroundStyle(.secondary)
                        if let e = p.lastLoginError, !e.isEmpty { Text(e).font(.caption).foregroundStyle(.red) }
                        else if let d = p.lastLoginAt { Text("Login ok \(d.itDateTime)").font(.caption2).foregroundStyle(.green) }
                    }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { confirmDelete = p } label: { Label("Rimuovi", systemImage: "trash") }
                        Button { Task { await engine.serverRelogin(p) } } label: { Label("Rifai login", systemImage: "arrow.clockwise") }.tint(.blue)
                    }
                }
                Button { showAdd = true } label: { Label("Aggiungi profilo mywellness", systemImage: "person.badge.plus") }
            } footer: {
                Text("Ogni profilo è un account Technogym mywellness. Le password restano cifrate sul NAS; il gateway fa il login e rinnova la sessione da solo. I profili \"famiglia\" sono visibili a tutti gli utenti del gateway.")
            }
            if let e = engine.lastError { Section { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote) } }
        }
        .navigationTitle("Profili mywellness")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await engine.refreshServer(force: true) }
        .alert("Rimuovere il profilo e le sue lezioni seguite?", isPresented: .init(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Rimuovi", role: .destructive) { if let p = confirmDelete { Task { await engine.serverDeleteProfile(p) } } }
            Button("Annulla", role: .cancel) {}
        } message: { Text(confirmDelete?.label ?? "") }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("Account Technogym mywellness") {
                        TextField("Etichetta (es. Daniela)", text: $label)
                        TextField("Email mywellness", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        PasswordField(title: "Password mywellness", text: $password)
                    }
                    Section("Centro") {
                        TextField("URL centro (es. wellnesstown)", text: $facility).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Stepper("Massimo prenotazioni attive: \(maxBookings)", value: $maxBookings, in: 1...30)
                        Toggle("Visibile solo a me", isOn: $isPrivate)
                        Toggle("È il mio account mywellness", isOn: $mine)
                    }
                    if let e = engine.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                .navigationTitle("Nuovo profilo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            busy = true
                            Task {
                                if await engine.serverAddProfile(label: label, username: email, password: password, facilityUrl: facility, maxBookings: maxBookings, isPrivate: isPrivate, mine: mine) {
                                    showAdd = false; label = ""; email = ""; password = ""
                                }
                                busy = false
                            }
                        } label: { if busy { ProgressView() } else { Text("Aggiungi").bold() } }
                        .disabled(email.isEmpty || password.isEmpty || busy)
                    }
                }
            }
        }
    }
}

/// Impostazioni del motore sul gateway (modificabili dall'amministratore).
struct ServerSettingsView: View {
    @EnvironmentObject var engine: BookingEngine
    @State private var s = GWSettings()
    @State private var loaded = false
    @State private var saved = false
    private var readOnly: Bool { !(engine.serverUser?.isAdmin ?? false) }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $s.followServerOpenTime) { Label("Segui l'orario del centro", systemImage: "building.2.crop.circle") }
                ForEach($s.openRules) { $r in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: r.pattern == "*" ? "asterisk.circle" : "textformat").foregroundStyle(.secondary)
                            TextField("Nome lezione (es. Reformer)", text: $r.pattern).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(r.pattern == "*")
                        }
                        HStack {
                            Stepper("Giorni prima: \(r.daysBefore)", value: $r.daysBefore, in: 0...30)
                            DatePicker("", selection: .init(get: { Calendar.current.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: Date()) ?? Date() },
                                                            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); r.hour = c.hour ?? 5; r.minute = c.minute ?? 0 }),
                                       displayedComponents: .hourAndMinute).labelsHidden()
                        }
                    }
                }
                .onDelete { idx in s.openRules.remove(atOffsets: idx) }
                Button { s.openRules.insert(GWOpenRule(pattern: "", daysBefore: 3, hour: 5, minute: 0), at: max(0, s.openRules.count - 1)) } label: { Label("Aggiungi regola", systemImage: "plus.circle") }
                Stepper("Anticipo: \(s.leadMilliseconds) ms", value: $s.leadMilliseconds, in: 0...3000, step: 100)
                Stepper("Insisti per \(s.burstSeconds) s dopo l'apertura", value: $s.burstSeconds, in: 10...600, step: 10)
            } header: { Text("Scheduler") } footer: {
                Text("Scrivi tu il testo da cercare nel nome della lezione (es. Reformer → 3 giorni); la prima regola che corrisponde decide giorni e ora, * vale per tutte le altre. Con \"Segui l'orario del centro\" attivo le regole servono solo quando mywellness non comunica l'apertura.")
            }
            Section {
                Stepper("Controlla ogni \(s.pollSeconds) s", value: $s.pollSeconds, in: 5...300, step: 5)
                Stepper("Giorni di calendario: \(s.daysAhead)", value: $s.daysAhead, in: 3...30)
                Toggle(isOn: $s.priorityNotifications) { Label("Notifiche prioritarie", systemImage: "bell.badge") }
            } header: { Text("Osservazione") } footer: {
                Text("Quando una classe è piena il gateway resta in lista d'attesa e controlla i posti liberi a questo intervallo (più fitto nelle ultime ore utili). Appena si libera un posto prenota e manda la notifica.")
            }
            if readOnly { Section { Text("Solo l'amministratore del gateway può modificare queste impostazioni.").font(.footnote).foregroundStyle(.secondary) } }
        }
        .disabled(readOnly)
        .navigationTitle("Scheduler del gateway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !readOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await engine.saveServerSettings(s); saved = true } }
                }
            }
        }
        .onAppear { if !loaded, let ss = engine.serverSettings { s = ss; loaded = true } }
        .task { if engine.serverSettings == nil { await engine.refreshServer(force: true) }; if let ss = engine.serverSettings, !loaded { s = ss; loaded = true } }
        .alert("Impostazioni salvate sul gateway", isPresented: $saved) { Button("OK") {} }
    }
}
