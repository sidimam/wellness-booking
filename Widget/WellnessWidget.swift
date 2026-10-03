import WidgetKit
import SwiftUI

/// Widget multi-misura: stato delle prossime lezioni seguite (home, lock screen, StandBy).
@main
struct WellnessWidgetBundle: WidgetBundle {
    var body: some Widget { WellnessWidget() }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { .init(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(.init(date: Date(), snapshot: context.isPreview ? .placeholder : SharedSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SharedSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct WellnessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedSnapshot.widgetKind, provider: SnapshotProvider()) { entry in
            WellnessWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Wellness Booking")
        .description(String(localized: "Prossime lezioni seguite, prenotazioni e osservazione."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WellnessWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snap: SharedSnapshot? { entry.snapshot }
    private var upcoming: [SharedSnapshot.Entry] {
        (snap?.entries ?? []).filter { $0.start > Date() }.sorted { $0.start < $1.start }
    }
    private var next: SharedSnapshot.Entry? { upcoming.first { $0.kind != "booked" } ?? upcoming.first }

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    // MARK: Lock screen

    private var inline: some View {
        if let n = next { Text("\(symbol(n.kind)) \(n.name) \(n.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))") }
        else { Text("Wellness Booking") }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: next.map { symbol($0.kind) } ?? "calendar").font(.title3)
                if let s = snap { Text("\(s.activeBookings)/\(s.maxBookings)").font(.caption2.monospacedDigit()) }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let n = next {
                HStack(spacing: 4) { Image(systemName: symbol(n.kind)); Text(n.name).bold().lineLimit(1) }
                Text(n.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute())).font(.caption)
                Text(n.state).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Wellness Booking").bold()
                Text("Nessuna lezione seguita").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Home screen

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark").foregroundStyle(Color.accentColor)
            Text("Wellness Booking").font(.caption.bold())
            Spacer()
            if let s = snap {
                Circle().fill(s.running ? Color.green : Color.secondary).frame(width: 8, height: 8)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let n = next {
                Image(systemName: symbol(n.kind)).font(.title2).foregroundStyle(color(n.kind))
                Text(n.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(n.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).font(.caption)
                Text(n.state).font(.caption2).foregroundStyle(color(n.kind)).lineLimit(1)
            } else {
                Text("Nessuna lezione seguita").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let s = snap { Text("Prenotazioni \(s.activeBookings)/\(s.maxBookings)").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if upcoming.isEmpty { Text("Nessuna lezione seguita").font(.footnote).foregroundStyle(.secondary); Spacer() }
            ForEach(upcoming.prefix(3)) { e in row(e) }
            Spacer(minLength: 0)
            footer
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if upcoming.isEmpty { Text("Nessuna lezione seguita").font(.footnote).foregroundStyle(.secondary) }
            ForEach(upcoming.prefix(7)) { e in row(e) }
            Spacer(minLength: 0)
            footer
        }
    }

    private func row(_ e: SharedSnapshot.Entry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(e.kind)).foregroundStyle(color(e.kind)).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.name).font(.footnote.bold()).lineLimit(1)
                Text(e.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(e.kind == "pending", e.fireAt.map { "Prenoto \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" } ?? e.state, e.state)
                .font(.caption2).foregroundStyle(color(e.kind)).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }

    private var footer: some View {
        HStack {
            if let s = snap {
                Text(s.running ? "Motore attivo" : "Motore fermo").font(.caption2).foregroundStyle(s.running ? .green : .secondary)
                Spacer()
                Text("Prenotazioni \(s.activeBookings)/\(s.maxBookings)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(_ kind: String) -> String {
        switch kind {
        case "booked": return "checkmark.seal.fill"
        case "watching": return "eye.fill"
        case "waitingList": return "person.2.wave.2.fill"
        case "bursting": return "bolt.fill"
        case "failed": return "exclamationmark.triangle.fill"
        case "expired": return "xmark.circle"
        default: return "clock"
        }
    }
    private func color(_ kind: String) -> Color {
        switch kind {
        case "booked": return .green
        case "watching", "waitingList": return .orange
        case "bursting": return .blue
        case "failed", "expired": return .red
        default: return .secondary
        }
    }
}

/// Testo condizionale compatto: `Text(cond, a, b)`.
private extension Text {
    init(_ condition: Bool, _ a: String, _ b: String) { self.init(condition ? a : b) }
}
