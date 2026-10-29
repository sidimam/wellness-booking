import SwiftUI

/// Avatar di un socio (foto pubblica o iniziale; i profili privati restano anonimi).
/// Con `zoomable` un tocco sulla foto la apre a tutto schermo (pizzica o doppio tocco per ingrandire).
struct MemberAvatar: View {
    let member: GWMember
    var size: CGFloat = 40
    var zoomable = false
    @State private var zoomed = false
    private var photoURL: URL? {
        guard !member.private, let u = member.pictureUrl, !u.isEmpty else { return nil }
        return URL(string: u)
    }
    var body: some View {
        if zoomable, let url = photoURL {
            Button { zoomed = true } label: { circle }
                .buttonStyle(.borderless)
                .accessibilityLabel("Ingrandisci la foto")
                .fullScreenCover(isPresented: $zoomed) { PhotoZoomView(url: url, title: member.displayName) }
        } else { circle }
    }
    private var circle: some View {
        Group {
            if let url = photoURL {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { initial }
            } else { initial }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
    private var initial: some View {
        ZStack {
            Circle().fill(member.private ? Color.secondary.opacity(0.3) : Color.accentColor.opacity(0.85))
            if member.private { Image(systemName: "person.fill.questionmark").imageScale(.medium).foregroundStyle(.white) }
            else { Text(String((member.fullName ?? member.nickName).prefix(1)).uppercased()).font(.system(size: size / 2.2, weight: .bold)).foregroundStyle(.white) }
        }
    }
}

/// Foto di un socio a tutto schermo: pizzica o doppio tocco per ingrandire, Chiudi o trascina in basso per uscire.
struct PhotoZoomView: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, base * $0.magnification)) }.onEnded { _ in base = scale })
                        .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; base = scale } }
                } placeholder: { ProgressView().tint(.white) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 120 && scale == 1 { dismiss() } })
    }
}

/// Riga di un socio: foto (toccabile per ingrandirla), nome e cognome con il nickname sotto,
/// quante volte visto, lezioni, posizioni in classifica. Un tocco sul testo apre la scheda (`onOpen`).
struct MemberRow: View {
    let member: GWMember
    var showJoined = false
    var onOpen: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 52, zoomable: true)
            if let open = onOpen {
                Button(action: open) { details }.buttonStyle(.borderless).tint(.primary)
            } else { details }
        }
    }
    private var details: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName).font(.headline).foregroundStyle(member.private ? .secondary : .primary).multilineTextAlignment(.leading)
                    if let w = member.bestWeekPosition { Text("🏆 #\(w)").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1).background(Color.yellow.opacity(0.25)).clipShape(Capsule()) }
                }
                if let n = member.secondaryNick { Text(n).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                if let c = member.classes, !c.isEmpty { Text(c.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    Text(member.seenCount > 1 ? "Visto \(member.seenCount) volte" : "Nuovo").font(.caption2).foregroundStyle(member.seenCount > 1 ? Color.green : .secondary)
                    if showJoined, let j = member.joinedOn, let d = ISO8601DateFormatter.lenient(j) { Text("iscritto \(d.itShortDay) \(d.itTime)").font(.caption2).foregroundStyle(.secondary) }
                    if let st = member.station, !st.isEmpty { Text("postazione \(st)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension ISO8601DateFormatter {
    /// Date ISO con o senza frazioni/offset (mywellness le manda in forme diverse).
    static func lenient(_ s: String) -> Date? {
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        if let d = b.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Rome")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }
}

/// Sezione "Partecipanti" nella scheda lezione: iscritti letti dal vivo dal gateway con lo storico.
struct ParticipantsSection: View {
    @EnvironmentObject var engine: BookingEngine
    let event: ClassEvent
    @State private var result: GWParticipants?
    @State private var error: String?
    @State private var loading = false
    @State private var selected: GWMember?

    var body: some View {
        Section {
            if loading && result == nil { HStack { ProgressView(); Text("Lettura degli iscritti da mywellness…").foregroundStyle(.secondary) } }
            if let e = error { Text(e).font(.footnote).foregroundStyle(.red) }
            if let r = result {
                if r.participants.isEmpty { Text("Nessun iscritto visibile.").foregroundStyle(.secondary) }
                ForEach(r.participants) { m in
                    MemberRow(member: m, showJoined: true) { selected = m }
                }
            }
        } header: {
            HStack { Text("Partecipanti"); Spacer(); if let r = result { Text("\(r.participants.count)").foregroundStyle(.secondary) } }
        } footer: {
            if let r = result, let o = r.observedAt, let d = ISO8601DateFormatter.lenient(o) { Text("Aggiornato \(d.itShortDay) \(d.itTime) · tocca il nome per lo storico, la foto per ingrandirla. Chi ha il profilo privato resta anonimo.") }
        }
        .task { await load() }
        .sheet(item: $selected) { m in NavigationStack { MemberDetailView(memberId: m.id) } }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { result = try await engine.participants(for: event); error = result?.liveError }
        catch { self.error = error.localizedDescription }
    }
}

/// Scheda di un socio: storico presenze e posizioni in classifica.
struct MemberDetailView: View {
    @EnvironmentObject var engine: BookingEngine
    let memberId: String
    @State private var detail: GWMemberDetail?
    @State private var error: String?

    var body: some View {
        List {
            if let d = detail {
                Section {
                    VStack(spacing: 8) {
                        MemberAvatar(member: d.member, size: 120, zoomable: true)
                        Text(d.member.displayName).font(.title2.weight(.semibold))
                        if let n = d.member.secondaryNick { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                        Text("Visto \(d.member.seenCount) volte").font(.footnote).foregroundStyle(.secondary)
                        if let f = ISO8601DateFormatter.lenient(d.member.firstSeen), let l = ISO8601DateFormatter.lenient(d.member.lastSeen) {
                            Text("dal \(f.itShortDay) · ultima volta \(l.itShortDay)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
                if let c = d.member.classes, !c.isEmpty { Section("Lezioni frequentate") { ForEach(c, id: \.self) { Text($0) } } }
                if !d.leaderboard.isEmpty {
                    Section("Classifica MOVEs") {
                        ForEach(d.leaderboard) { l in LabeledContent("\(l.trend == "week" ? String(localized: "settimana") : String(localized: "mese")) \(l.period)", value: "#\(l.position) · \(l.moves) MOVEs") }
                    }
                }
                Section("Presenze registrate (\(d.attendance.count))") {
                    ForEach(d.attendance) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.body)
                            Text("\(a.start.itShortDay) \(a.start.itTime)" + (a.room.map { " · \($0)" } ?? "") + (a.station.map { " · postazione \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let ex = d.member.extra, !ex.isEmpty {
                    Section { DisclosureGroup { ForEach(ex.keys.sorted(), id: \.self) { k in LabeledContent(k) { Text(ex[k]!.display).font(.caption.monospaced()) } } } label: { Label("Dati tecnici", systemImage: "info.circle").foregroundStyle(.secondary) } }
                }
            } else if let e = error { Text(e).foregroundStyle(.red) } else { ProgressView() }
        }
        .navigationTitle(detail?.member.displayName ?? "Socio")
        .navigationBarTitleDisplayMode(.inline)
        .task { do { detail = try await engine.member(memberId) } catch { self.error = error.localizedDescription } }
    }
}

/// Persone del centro: classifica MOVEs (settimana/mese, periodi passati) e compagni di corso.
struct PeopleView: View {
    @EnvironmentObject var engine: BookingEngine
    @State private var trend = "week"
    @State private var period: String?
    @State private var board: GWLeaderboard?
    @State private var members: [GWMember] = []
    @State private var query = ""
    @State private var error: String?
    @State private var selected: GWMember?

    var body: some View {
        List {
            Section {
                Picker("Periodo", selection: $trend) { Text("Settimana").tag("week"); Text("Mese").tag("month") }.pickerStyle(.segmented)
                if let b = board, !b.periods.isEmpty {
                    Picker("Classifica", selection: Binding(get: { period ?? b.period }, set: { period = $0 })) { ForEach(b.periods, id: \.self) { Text($0).tag($0) } }
                }
                if let b = board {
                    if b.entries.isEmpty { Text("Nessuna classifica salvata ancora: il gateway la legge ogni ora.").font(.footnote).foregroundStyle(.secondary) }
                    if b.entries.count >= 1 { podium(Array(b.entries.prefix(3))) }
                    ForEach(b.entries.dropFirst(3)) { e in
                        HStack(spacing: 12) {
                            Text("\(e.position)").font(.body.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                            MemberAvatar(member: GWMember(id: e.memberId ?? "", nickName: e.nickName, pictureUrl: e.pictureUrl, private: false, firstSeen: "", lastSeen: "", seenCount: 0), size: 32)
                            Text(e.nickName)
                            Spacer()
                            Text("\(e.moves) MOVEs").font(.body.weight(.semibold).monospacedDigit())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let id = e.memberId, !id.isEmpty { selected = GWMember(id: id, nickName: e.nickName, pictureUrl: e.pictureUrl, private: false, firstSeen: "", lastSeen: "", seenCount: 0) } }
                    }
                }
            } header: { Text("Classifica MOVEs · \(engine.selectedProfile?.facilityName ?? "")") } footer: {
                Text("La stessa classifica dell'app Technogym (Sfide). Le persone già viste in una lezione sono toccabili.")
            }
            Section {
                ForEach(members) { m in MemberRow(member: m) { selected = m } }
                if members.isEmpty { Text("Nessun socio ancora registrato: apri una lezione e la sezione Partecipanti, oppure aspetta la lettura automatica.").font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Compagni di corso (\(members.count))") } footer: {
                Text("Soci visti nelle lezioni che segui o hai prenotato, i più frequenti prima. Dati pubblici di mywellness: nickname, foto, nome e cognome del profilo pubblico; i profili privati restano anonimi.")
            }
            if let e = error { Section { Text(e).foregroundStyle(.red).font(.footnote) } }
        }
        .searchable(text: $query, prompt: "Cerca nome o nickname")
        .navigationTitle("Persone")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .onChange(of: trend) { _, _ in period = nil; Task { await loadBoard() } }
        .onChange(of: period) { _, _ in Task { await loadBoard() } }
        .onChange(of: query) { _, _ in Task { await loadMembers() } }
        .refreshable { await loadAll() }
        .sheet(item: $selected) { m in NavigationStack { MemberDetailView(memberId: m.id) } }
    }
    @ViewBuilder private func podium(_ top: [GWLeaderboardRow]) -> some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(top) { e in
                VStack(spacing: 4) {
                    Text("\(e.position)").font(.caption).foregroundStyle(.secondary)
                    MemberAvatar(member: GWMember(id: e.memberId ?? "", nickName: e.nickName, pictureUrl: e.pictureUrl, private: false, firstSeen: "", lastSeen: "", seenCount: 0), size: e.position == 1 ? 84 : 64)
                    Text(e.nickName).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text("\(e.moves)").font(.title3.weight(.bold).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { if let id = e.memberId, !id.isEmpty { selected = GWMember(id: id, nickName: e.nickName, pictureUrl: e.pictureUrl, private: false, firstSeen: "", lastSeen: "", seenCount: 0) } }
            }
        }
        .padding(.vertical, 6)
    }
    private func loadAll() async { await loadBoard(); await loadMembers() }
    private func loadBoard() async {
        do { board = try await engine.leaderboard(trend: trend, period: period); error = nil } catch { self.error = error.localizedDescription }
    }
    private func loadMembers() async {
        do { members = try await engine.members(query: query); error = nil } catch { self.error = error.localizedDescription }
    }
}

#if DEBUG
/// Elenco partecipanti di prova per i test visivi (`-demoParticipants`, solo Debug). Dati inventati, foto della famiglia.
struct DemoParticipantsView: View {
    private let members: [GWMember] = [
        GWMember(id: "d1", nickName: "daniela.manieri", firstName: "Daniela", lastName: "Manieri", pictureUrl: "https://publicmedia.mywellness.com/users/photo/x0101x/35d415cc-4283-469d-8b31-9b6a40ac21ac_large.jpg", private: false, firstSeen: "2026-10-01T08:00:00Z", lastSeen: "2026-10-29T08:00:00Z", seenCount: 12, classes: ["Group Reformer", "PILATES"], joinedOn: "2026-10-26T07:01:00Z", bestWeekPosition: 3),
        GWMember(id: "d2", nickName: "mario_r", firstName: "Mario Giovanni", lastName: "Rossi Bianchi", pictureUrl: nil, private: false, firstSeen: "2026-10-01T08:00:00Z", lastSeen: "2026-10-29T08:00:00Z", seenCount: 1, classes: ["HYDROBIKE"]),
        GWMember(id: "d3", nickName: "Giusi", pictureUrl: nil, private: false, firstSeen: "2026-10-01T08:00:00Z", lastSeen: "2026-10-29T08:00:00Z", seenCount: 4, classes: ["INDOOR WALK"]),
        GWMember(id: "d4", nickName: "*******", pictureUrl: nil, private: true, firstSeen: "2026-10-01T08:00:00Z", lastSeen: "2026-10-29T08:00:00Z", seenCount: 2),
    ]
    @State private var opened: String?
    var body: some View {
        NavigationStack {
            List {
                Section("Partecipanti") { ForEach(members) { m in MemberRow(member: m, showJoined: true) { opened = m.displayName } } }
                if let o = opened { Section { Text("Aperta la scheda di \(o)") } }
            }
            .navigationTitle("Demo partecipanti")
        }
    }
}
#endif
