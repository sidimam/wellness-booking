import SwiftUI
import BackgroundTasks

@main
struct WellnessBookingApp: App {
    @StateObject private var engine = BookingEngine.shared
    @AppStorage("themeMode") private var themeMode = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    static let refreshTaskId = "com.sdimambro.wellness-booking.refresh"

    init() {
        Store.startObservingCloud()
        WatchBridge.shared.activate()
        _ = Notifier.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .tint(AppIconColor.tint(for: engine.settings.accent))
                .preferredColorScheme(ThemeMode(rawValue: themeMode)?.scheme)
                .onAppear { AppIconColor.apply(engine.settings.accent) }
                .onChange(of: engine.settings.accent) { _, new in AppIconColor.apply(new) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Notifier.shared.scheduleReminders(for: engine.items, settings: engine.settings)
                scheduleBackgroundRefresh()
            case .active:
                if engine.isRunning { Task { await engine.refreshClasses() } }
            default: break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskId)) {
            // Best effort: iOS decide quando eseguirlo (non è puntuale). Controlla posti liberi e tenta.
            await BookingEngine.shared.backgroundCheck()
            await scheduleBackgroundRefresh()
        }
    }

    private func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
