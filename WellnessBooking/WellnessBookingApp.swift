import SwiftUI
import BackgroundTasks

@main
struct WellnessBookingApp: App {
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
    @StateObject private var engine = BookingEngine.shared
    @StateObject private var quickActions = QuickActionRouter.shared
    @AppStorage("themeMode") private var themeMode = ThemeMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    static let refreshTaskId = "com.sdimambro.wellness-booking.refresh"
    static let processingTaskId = "com.sdimambro.wellness-booking.processing"

    init() {
        Store.startObservingCloud()
        WatchBridge.shared.activate()
        _ = Notifier.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(quickActions)
                .tint(AppIconColor.tint(for: engine.settings.accent))
                .preferredColorScheme(ThemeMode(rawValue: themeMode)?.scheme)
                .modifier(AppLocaleModifier())
                .onAppear { AppIconColor.apply(engine.settings.accent); HomeScreenShortcuts.install(running: engine.isRunning) }
                .onChange(of: engine.settings.accent) { _, new in AppIconColor.apply(new) }
                .onChange(of: engine.isRunning) { _, r in HomeScreenShortcuts.install(running: r) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                Notifier.shared.scheduleReminders(for: engine.items, settings: engine.settings)
                Self.scheduleBackgroundWork(deadline: engine.nextBackgroundDeadline)
                HomeScreenShortcuts.install(running: engine.isRunning)
            case .active:
                if engine.isServerMode { Task { await engine.resumeServer() } }
                else if engine.isRunning { Task { await engine.refreshClasses() } }
            default: break
            }
        }
        // Best effort: iOS decide quando eseguirli (non sono puntuali). Un giro di scheduler/osservazione.
        .backgroundTask(.appRefresh(Self.refreshTaskId)) {
            await BookingEngine.shared.backgroundCheck()
            await Self.scheduleBackgroundWork(deadline: BookingEngine.shared.nextBackgroundDeadline)
        }
        .backgroundTask(.appRefresh(Self.processingTaskId)) {
            await BookingEngine.shared.backgroundCheck()
            await Self.scheduleBackgroundWork(deadline: BookingEngine.shared.nextBackgroundDeadline)
        }
    }

    /// Chiede a iOS un risveglio: refresh periodico + task di elaborazione il più vicino possibile alla scadenza utile.
    static func scheduleBackgroundWork(deadline: Date?) {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        refresh.earliestBeginDate = deadline ?? Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)
        let proc = BGProcessingTaskRequest(identifier: processingTaskId)
        proc.requiresNetworkConnectivity = true
        proc.requiresExternalPower = false
        proc.earliestBeginDate = deadline ?? Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(proc)
    }
}
