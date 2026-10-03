import SwiftUI

/// Presentazione iniziale (3 pagine) con accesso diretto al login.
struct WalkthroughView: View {
    @EnvironmentObject var engine: BookingEngine
    var done: () -> Void
    @State private var page = 0
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var gwURL = ""
    @State private var gwUser = ""
    @State private var gwPass = ""
    @State private var gwBusy = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                pageView(icon: "calendar.badge.checkmark", title: "Wellness Booking",
                         text: String(localized: "Scegli le lezioni che ti interessano: l'app le prenota da sola all'apertura delle prenotazioni, anche alle 5 del mattino.")).tag(0)
                pageView(icon: "eye.fill", title: String(localized: "Osservazione"),
                         text: String(localized: "Se una classe è piena, l'app entra in lista d'attesa e controlla di continuo i posti: appena qualcuno disdice, prenota al volo e ti avvisa con una notifica prioritaria, anche su Apple Watch.")).tag(1)
                serverPage.tag(2)
                loginPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                Button("Salta") { done() }.foregroundStyle(.secondary)
                Spacer()
                if page < 3 { Button("Avanti") { withAnimation { page += 1 } }.buttonStyle(.borderedProminent) }
            }
            .padding()
        }
        .onAppear { email = engine.username; password = engine.password }
    }

    private func pageView(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon).font(.system(size: 72)).foregroundStyle(Color.accentColor)
            Text(title).font(.largeTitle.bold())
            Text(text).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            Spacer()
        }
    }

    private var serverPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "server.rack").font(.system(size: 64)).foregroundStyle(Color.accentColor)
            Text("Server di casa").font(.title.bold())
            Text("Consigliato: collega il container wellness-gateway del tuo NAS. Prenota lui, sempre acceso, per tutta la famiglia, e ti avvisa con le notifiche push. Senza server l'app lavora da sola ma solo in primo piano.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Form {
                ServerLoginFields(url: $gwURL, username: $gwUser, password: $gwPass, busy: $gwBusy) { done() }
                if let e = engine.lastError, !gwUser.isEmpty { Text(e).font(.footnote).foregroundStyle(.red) }
            }
            .frame(height: 260).scrollContentBackground(.hidden)
            Button("Continua senza server") { withAnimation { page = 3 } }.font(.footnote)
            Spacer()
        }
        .onAppear { if gwURL.isEmpty { gwURL = engine.settings.serverURL } }
    }

    private var loginPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.badge.key").font(.system(size: 64)).foregroundStyle(Color.accentColor)
            Text("Accedi a mywellness").font(.title.bold())
            Text("Usa email e password dell'account Technogym mywellness con cui prenoti al centro.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            VStack(spacing: 10) {
                TextField("Email", text: $email).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password).textContentType(.password)
            }
            .textFieldStyle(.roundedBorder).padding(.horizontal, 32)
            Button {
                busy = true
                engine.username = email.trimmingCharacters(in: .whitespaces); engine.password = password
                Task {
                    if await engine.login() { Notifier.shared.requestAuthorization(); await engine.refreshClasses(); done() }
                    busy = false
                }
            } label: {
                HStack { if busy { ProgressView().tint(.white) }; Text("Accedi e inizia").bold() }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).padding(.horizontal, 32)
            .disabled(email.isEmpty || password.isEmpty || busy)
            if let e = engine.lastError { Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 32) }
            Spacer()
        }
    }
}
