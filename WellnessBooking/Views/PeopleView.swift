import SwiftUI

/// Avatar di un socio (foto pubblica o iniziale; i profili privati restano anonimi).
struct MemberAvatar: View {
    let member: GWMember
    var size: CGFloat = 40
    var body: some View {
        Group {
            if !member.private, let u = member.pictureUrl, !u.isEmpty, let url = URL(string: u) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { initial }
            } else { initial }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
    private var initial: some View {
        ZStack {
            Circle().fill(member.private ? Color.secondary.opacity(0.3) : Color.accentColor.opacity(0.85))
            if member.private { Image(systemName: "person.fill.questionmark").imageScale(.medium).foregroundStyle(.white) }
            else { Text(String(member.nickName.prefix(1)).uppercased()).font(.system(size: size / 2.2, weight: .bold)).foregroundStyle(.white) }
        }
    }
}

/// Riga di un socio: foto, nickname, quante volte visto, lezioni, posizioni in classifica.
struct MemberRow: View {
    let member: GWMember
    var showJoined = false
    var body: some View {
        HStack(spacing: 12) {
            MemberAvatar(member: member, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName).font(.body.weight(.semibold)).foregroundStyle(member.private ? .secondary : .primary)
                    if let w = member.bestWeekPosition { Text("🏆 #\(w)").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1).background(Color.yellow.opacity(0.25)).clipShape(Capsule()) }
                }
                if let c = member.classes, !c.isEmpty { Text(c.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    Text(member.seenCount > 1 ? "Visto \(member.seenCount) volte" : "Nuovo").font(.caption2).foregroundStyle(member.seenCount > 1 ? Color.green : .secondary)
                    if showJoined, let j = member.joinedOn, let d = ISO8601DateFormatter.lenient(j) { Text("iscritto \(d.itShortDay) \(d.itTime)").font(.caption2).foregroundStyle(.secondary) }
                    if let st = member.station, !st.isEmpty { Text("postazione \(st)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Spacer()
        }
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
                    Button { selected = m } label: { MemberRow(member: m, showJoined: true) }.buttonStyle(.plain)
                }
            }
        } header: {
            HStack { Text("Partecipanti"); Spacer(); if let r = result { Text("\(r.participants.count)").foregroundStyle(.secondary) } }
        } footer: {
            if let r = result, let o = r.observedAt, let d = ISO8601DateFormatter.lenient(o) { Text("Aggiornato \(d.itShortDay) \(d.itTime) · tocca una persona per lo storico. Chi ha il profilo privato resta anonimo.") }
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
                        MemberAvatar(member: d.member, size: 88)
                        Text(d.member.displayName).font(.title2.weight(.semibold))
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
                ForEach(members) { m in Button { selected = m } label: { MemberRow(member: m) }.buttonStyle(.plain) }
                if members.isEmpty { Text("Nessun socio ancora registrato: apri una lezione e la sezione Partecipanti, oppure aspetta la lettura automatica.").font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Compagni di corso (\(members.count))") } footer: {
                Text("Soci visti nelle lezioni che segui o hai prenotato, i più frequenti prima. Dati pubblici di mywellness: nickname, foto, profilo privato.")
            }
            if let e = error { Section { Text(e).foregroundStyle(.red).font(.footnote) } }
        }
        .searchable(text: $query, prompt: "Cerca nickname")
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
