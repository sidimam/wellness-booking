import Foundation

/// Persistenza: UserDefaults + iCloud Key-Value Store (sync tra iPhone/iPad).
enum Store {
    private static let defaults = UserDefaults.standard
    private static let cloud = NSUbiquitousKeyValueStore.default
    static var onCloudChange: (() -> Void)?

    private static let kSettings = "settings.v1"
    private static let kItems = "items.v1"
    private static let kLog = "log.v1"

    private static var cloudEnabled: Bool { loadSettings().iCloudSync }

    static func startObservingCloud() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloud, queue: .main) { _ in
            // copia i valori cloud in locale, poi avvisa
            for k in [kSettings, kItems] { if let d = cloud.data(forKey: k) { defaults.set(d, forKey: k) } }
            onCloudChange?()
        }
        cloud.synchronize()
    }

    private static func save<T: Encodable>(_ v: T, key: String, toCloud: Bool) {
        guard let d = try? JSONEncoder().encode(v) else { return }
        defaults.set(d, forKey: key)
        if toCloud && cloudEnabled { cloud.set(d, forKey: key); cloud.synchronize() }
    }
    private static func load<T: Decodable>(_ t: T.Type, key: String) -> T? {
        if let d = defaults.data(forKey: key), let v = try? JSONDecoder().decode(t, from: d) { return v }
        if let d = cloud.data(forKey: key), let v = try? JSONDecoder().decode(t, from: d) { return v }
        return nil
    }

    static func saveSettings(_ s: AppSettings) { save(s, key: kSettings, toCloud: true) }
    static func loadSettings() -> AppSettings { load(AppSettings.self, key: kSettings) ?? AppSettings() }
    static func saveItems(_ i: [WatchItem]) { save(i, key: kItems, toCloud: true) }
    static func loadItems() -> [WatchItem] { load([WatchItem].self, key: kItems) ?? [] }
    static func saveLog(_ l: [LogLine]) { save(Array(l.prefix(200)), key: kLog, toCloud: false) }
    static func loadLog() -> [LogLine] { load([LogLine].self, key: kLog) ?? [] }
}
