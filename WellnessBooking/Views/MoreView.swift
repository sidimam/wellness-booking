import SwiftUI
import UserNotifications

/// Tab "Altro": account, centro, scheduler, watchdog, aspetto, notifiche, log, info.
struct MoreView: View {
    @EnvironmentObject var engine: BookingEngine
    @AppStorage("themeMode") private var themeMode = ThemeMode.system.rawValue
    @AppStorage("walkthroughDone") private var walkthroughDone = false
    @State private var email = ""
    @State private var password = ""
    @State private var testing = false
    @State private var facilityUrl = ""
    @State private var notifStatus = "…"
    @State private var openTime = Date()
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Email mywellness", text: $email)
                    .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
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
                Text("Le stesse credenziali della web app mywellness. Sono salvate solo nel Keychain di questo iPhone.")
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
            } header: { Text("Centro") } footer: {
                Text("L'URL è la parte finale dell'indirizzo del widget: widgets.mywellness.com/facility/‹url›/schedule/…")
            }

            Section {
                Toggle(isOn: $engine.settings.useCustomOpenTime) { Label("Orario personalizzato", systemImage: "clock.badge") }
                if engine.settings.useCustomOpenTime {
                    DatePicker("Prenota alle", selection: $openTime, displayedComponents: .hourAndMinute)
                        .onChange(of: openTime) { _, d in
                            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                            engine.settings.customOpenHour = c.hour ?? 5; engine.settings.customOpenMinute = c.minute ?? 0
                        }
                    Stepper("Giorni prima della lezione: \(engine.settings.customDaysBefore)", value: $engine.settings.customDaysBefore, in: 0...14)
                }
                Stepper("Anticipo: \(engine.settings.leadMilliseconds) ms", value: $engine.settings.leadMilliseconds, in: 0...3000, step: 100)
                Stepper("Insisti per \(engine.settings.burstSeconds) s dopo l'apertura", value: $engine.settings.burstSeconds, in: 10...600, step: 10)
            } header: { Text("Scheduler") } footer: {
                Text(engine.settings.useCustomOpenTime
                     ? "L'app prenota \(engine.settings.customDaysBefore) giorni prima alle \(String(format: "%02d:%02d", engine.settings.customOpenHour, engine.settings.customOpenMinute))."
                     : "Usa l'orario di apertura comunicato dal centro (per Wellness Town: 3 giorni prima alle 05:00). Attiva l'orario personalizzato per cambiarlo.")
            }

            Section {
                Stepper("Controlla ogni \(engine.settings.pollSeconds) s", value: $engine.settings.pollSeconds, in: 5...300, step: 5)
                Toggle(isOn: $engine.settings.keepScreenAwake) { Label("Tieni lo schermo acceso", systemImage: "sun.max") }
            } header: { Text("Watchdog") } footer: {
                Text("Quando una classe è piena l'app resta in lista d'attesa e controlla i posti liberi a questo intervallo (più fitto nelle ultime ore utili). Appena si libera un posto prenota e ti avvisa.")
            }

            Section {
                Toggle(isOn: $engine.settings.priorityNotifications) { Label("Notifiche prioritarie", systemImage: "bell.badge") }
                Toggle(isOn: $engine.settings.hapticsEnabled) { Label("Vibrazione", systemImage: "iphone.radiowaves.left.and.right") }
                LabeledContent { Text(notifStatus).foregroundStyle(.secondary) } label: { Label("Permesso notifiche", systemImage: "bell") }
                Button { openNotificationSettings() } label: { Label("Impostazioni notifiche di iOS", systemImage: "gear") }
                Button { Notifier.shared.notify(title: "Notifica di prova", body: "Così ti avviso quando prenoto o si libera un posto.", priority: engine.settings.priorityNotifications) } label: {
                    Label("Invia notifica di prova", systemImage: "paperplane")
                }
            } header: { Text("Notifiche") } footer: {
                Text("Le notifiche prioritarie (Time Sensitive) arrivano anche con Focus o Non disturbare attivi e compaiono su Apple Watch.")
            }

            Section {
                Picker(selection: $themeMode) { ForEach(ThemeMode.allCases) { Text($0.label).tag($0.rawValue) } } label: { Label("Aspetto", systemImage: "circle.lefthalf.filled") }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Colore app", systemImage: "paintpalette")
                    IconColorPicker(selection: $engine.settings.accent)
                }
                Toggle(isOn: $engine.settings.iCloudSync) { Label("Sincronizza con iCloud", systemImage: "icloud") }
            } header: { Text("Impostazioni app") } footer: {
                Text("Il colore cambia anche l'icona. iCloud sincronizza impostazioni e lezioni selezionate tra i tuoi dispositivi (non la password).")
            }

            Section("Supporto") {
                NavigationLink { LogView() } label: { Label("Registro attività", systemImage: "doc.text.magnifyingglass") }
                Button { walkthroughDone = false } label: { Label("Rivedi la presentazione", systemImage: "sparkles") }
            }

            Section("Informazioni app") {
                LabeledContent("Versione", value: appVersionString())
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
            openTime = Calendar.current.date(bySettingHour: engine.settings.customOpenHour, minute: engine.settings.customOpenMinute, second: 0, of: Date()) ?? Date()
            refreshNotifStatus()
        }
    }

    private func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let t: String
            switch s.authorizationStatus {
            case .authorized: t = s.timeSensitiveSetting == .enabled ? "Attive (prioritarie ok)" : "Attive"
            case .provisional: t = "Riepilogo"
            case .denied: t = "Disattivate"
            case .notDetermined: t = "Non richieste"
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

struct LogView: View {
    @EnvironmentObject var engine: BookingEngine
    var body: some View {
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
