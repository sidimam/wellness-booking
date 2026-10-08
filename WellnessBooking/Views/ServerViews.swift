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
                        if r.pattern != "*" {
                            Stepper(r.maxBookings == 0 ? "Max prenotazioni: solo limite profilo" : "Max prenotazioni: \(r.maxBookings)", value: $r.maxBookings, in: 0...20)
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
                Text("Scrivi tu il testo da cercare nel nome della lezione (es. Reformer → 3 giorni alle 05:01, massimo 3 prenotazioni attive). L'ora viene sempre dalla regola; con \"Segui l'orario del centro\" il giorno di apertura è quello comunicato da mywellness. \"Max prenotazioni\" è una quota separata per quel tipo di lezione (es. Reformer 3): quelle lezioni non contano nel limite del profilo.")
            }
            Section {
                Stepper("Controlla ogni \(s.pollSeconds) s", value: $s.pollSeconds, in: 5...300, step: 5)
                Stepper("Vicino alla lezione ogni \(s.nearPollSeconds) s", value: $s.nearPollSeconds, in: 2...60)
                Stepper("Vicino alla lezione = ultime \(s.nearHours) ore", value: $s.nearHours, in: 1...24)
                Stepper("Giorni di calendario: \(s.daysAhead)", value: $s.daysAhead, in: 3...30)
                Toggle(isOn: $s.priorityNotifications) { Label("Notifiche prioritarie", systemImage: "bell.badge") }
            } header: { Text("Osservazione") } footer: {
                Text("Quando una classe è piena il gateway resta in lista d'attesa e legge i posti liberi dal calendario pubblico (senza usare il tuo account) a questo ritmo, più fitto nelle ultime ore. Appena compare un posto prenota subito, con tentativi ravvicinati, e manda la notifica.")
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


/// Scheda del profilo mywellness dell'utente collegato: tutto ciò che il gateway riceve da Technogym al login.
struct ProfileDetailView: View {
    @EnvironmentObject var engine: BookingEngine
    let profile: GWProfile
    @State private var showAddCenter = false
    @State private var newCenter = ""
    @State private var newCenterMax = 5
    @State private var busy = false
    @State private var confirmRemove: GWProfile?

    /// Tutti i centri dello stesso account mywellness (un profilo per centro).
    private var centers: [GWProfile] { engine.profiles.filter { $0.username == profile.username }.sorted { $0.facilityName < $1.facilityName } }

    private static let knownLabels: [String: LocalizedStringResource] = [
        "id": "ID utente", "firstName": "Nome", "lastName": "Cognome", "nickName": "Nickname", "email": "Email",
        "gender": "Genere", "birthDate": "Data di nascita", "dateOfBirth": "Data di nascita", "culture": "Lingua",
        "language": "Lingua", "measurementSystem": "Unità di misura", "unitOfMeasure": "Unità di misura",
        "facilityName": "Centro", "facilityId": "ID centro", "currentFacilityId": "ID centro", "userType": "Tipo utente",
        "externalId": "ID esterno", "phoneNumber": "Telefono", "mobilePhone": "Cellulare", "address": "Indirizzo",
        "city": "Città", "country": "Paese", "zipCode": "CAP", "timeZone": "Fuso orario", "height": "Altezza", "weight": "Peso",
        "createdOn": "Iscritto dal", "lastLogin": "Ultimo accesso", "privacyAccepted": "Privacy accettata",
        "hasPrivateProfile": "Profilo privato", "isGuest": "Ospite", "mobileNumber": "Cellulare", "status": "Stato",
        "accountUsername": "Nome account", "defaultCulture": "Lingua predefinita", "userCultureInfo": "Impostazioni regionali",
        "timeZoneWindowsId": "Fuso orario", "canBeMultipleUser": "Account condiviso"
    ]
    private static let hidden: Set<String> = ["pictureUrl", "thumbPictureUrl", "picture", "thumbUrl", "pictureHttps", "credentialId", "displayBirthDate"]

    private var rows: [(key: String, label: String, value: String)] {
        guard let id = profile.identity else { return [] }
        return id.keys.sorted().compactMap { k in
            guard !Self.hidden.contains(k), let v = id[k] else { return nil }
            var text = v.display
            if text.isEmpty { return nil }
            if let d = ISO8601DateFormatter().date(from: text) ?? Self.plainDate(text) { text = d.itDateTime }
            let label = Self.knownLabels[k].map { String(localized: $0) } ?? Self.humanize(k)
            return (k, label, text)
        }
    }
    private static func plainDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Rome")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd"] { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
    private static func humanize(_ key: String) -> String {
        var out = ""
        for ch in key { if ch.isUppercase, !out.isEmpty { out.append(" ") }; out.append(ch) }
        return out.prefix(1).uppercased() + out.dropFirst().lowercased()
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ProfileAvatar(profile: profile, size: 96)
                    Text(profile.displayName ?? profile.label).font(.title2.weight(.semibold))
                    if let n = profile.nickName, !n.isEmpty { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                    Text(profile.email ?? profile.username).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(centers) { c in
                    Button { engine.selectProfile(c.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: c.id == engine.selectedProfile?.id ? "checkmark.circle.fill" : "building.2").foregroundStyle(c.id == engine.selectedProfile?.id ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.facilityName).foregroundStyle(.primary)
                                Text("Prenotazioni attive \(c.activeBookings)/\(c.maxBookings)" + (c.limits ?? []).map { " · \($0.pattern) \($0.active)/\($0.max)" }.joined()).font(.caption).foregroundStyle(.secondary)
                                if let e = c.lastLoginError, !e.isEmpty { Text(e).font(.caption).foregroundStyle(.red) }
                                else if let d = c.lastLoginAt { Text("Ultimo login mywellness \(d.itDateTime)").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if centers.count > 1 { Button(role: .destructive) { confirmRemove = c } label: { Label("Rimuovi centro", systemImage: "trash") } }
                    }
                }
                Button { newCenterMax = profile.maxBookings; showAddCenter = true } label: { Label("Aggiungi centro Technogym", systemImage: "plus.circle") }
            } header: { Text(centers.count > 1 ? "Centri (\(centers.count))" : "Centro") } footer: {
                Text("Lo stesso account mywellness può essere iscritto a più centri: ogni centro ha il suo calendario, le sue lezioni seguite e il suo limite. Tocca un centro per renderlo attivo in Lezioni e Prenotazioni.")
            }
            Section {
                if rows.isEmpty {
                    Text("Il gateway non ha ancora salvato i dettagli del profilo: rifai il login mywellness (aggiornamento alla v0.1.15 o successiva).").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.key) { r in
                        LabeledContent(r.label) { Text(r.value).multilineTextAlignment(.trailing).textSelection(.enabled) }
                    }
                }
            } header: { Text("Dati Technogym mywellness") } footer: {
                Text("Sono i dati che mywellness restituisce al login del tuo account; il gateway li conserva senza token né password.")
            }
            Section {
                Button { Task { await engine.serverRelogin(profile) } } label: { Label("Aggiorna dal mywellness (nuovo login)", systemImage: "arrow.clockwise") }
            }
        }
        .navigationTitle("Il mio profilo")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await engine.refreshServer(force: true) }
        .alert("Rimuovere questo centro e le sue lezioni seguite?", isPresented: .init(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Rimuovi", role: .destructive) { if let c = confirmRemove { Task { await engine.serverDeleteProfile(c) } } }
            Button("Annulla", role: .cancel) {}
        } message: { Text(confirmRemove?.facilityName ?? "") }
        .sheet(isPresented: $showAddCenter) {
            NavigationStack {
                Form {
                    Section {
                        TextField("URL centro (es. wellnesstown)", text: $newCenter).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Stepper("Massimo prenotazioni attive: \(newCenterMax)", value: $newCenterMax, in: 1...30)
                    } footer: {
                        Text("È la parte finale dell'indirizzo del widget mywellness del centro (widgets.mywellness.com/facility/<URL>/…). Il gateway usa le stesse credenziali mywellness di questo profilo.")
                    }
                    if let e = engine.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                }
                .navigationTitle("Nuovo centro")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { showAddCenter = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            busy = true
                            Task { if await engine.serverAddCenter(from: profile, facilityUrl: newCenter, maxBookings: newCenterMax) { showAddCenter = false; newCenter = "" }; busy = false }
                        } label: { if busy { ProgressView() } else { Text("Aggiungi").bold() } }
                        .disabled(newCenter.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                }
            }
        }
    }
}
