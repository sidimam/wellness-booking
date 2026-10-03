import Foundation

/// Snapshot condiviso app ⇄ widget tramite App Group (file JSON nel container condiviso).
struct SharedSnapshot: Codable {
    struct Entry: Codable, Identifiable {
        var id: String
        var name: String
        var start: Date
        var end: Date
        var state: String       // etichetta localizzata
        var kind: String        // pending | bursting | watching | waitingList | booked | failed | expired
        var fireAt: Date?
        var places: Int?
        var maxPlaces: Int?
    }
    var running: Bool
    var loggedIn: Bool
    var activeBookings: Int
    var maxBookings: Int
    var updated: Date
    var entries: [Entry]

    static let appGroup = "group.com.sdimambro.wellness-booking"
    static let widgetKind = "WellnessBookingWidget"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("snapshot.json")
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> SharedSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }

    static let placeholder = SharedSnapshot(running: true, loggedIn: true, activeBookings: 2, maxBookings: 5, updated: Date(), entries: [
        .init(id: "1", name: "Group Reformer", start: Date().addingTimeInterval(86400 * 2), end: Date().addingTimeInterval(86400 * 2 + 2700),
              state: "In attesa", kind: "pending", fireAt: Date().addingTimeInterval(3600 * 5), places: 0, maxPlaces: 8),
        .init(id: "2", name: "Group Reformer", start: Date().addingTimeInterval(86400 * 4), end: Date().addingTimeInterval(86400 * 4 + 2700),
              state: "Osservazione: piena", kind: "watching", fireAt: nil, places: 0, maxPlaces: 8),
        .init(id: "3", name: "Pilates", start: Date().addingTimeInterval(86400), end: Date().addingTimeInterval(86400 + 2700),
              state: "Prenotata", kind: "booked", fireAt: nil, places: 1, maxPlaces: 10),
    ])
}
