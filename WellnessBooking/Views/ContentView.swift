import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: BookingEngine
    @EnvironmentObject var router: QuickActionRouter
    @AppStorage("walkthroughDone") private var walkthroughDone = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { ClassesView() }
                .tabItem { Label("Lezioni", systemImage: "calendar") }.tag(0)
            NavigationStack { WatchListView() }
                .tabItem { Label("Prenotazioni", systemImage: "checkmark.circle") }
                .badge(engine.items.filter { !$0.state.isTerminal }.count).tag(1)
            NavigationStack { MoreView() }
                .tabItem { Label("Altro", systemImage: "ellipsis.circle") }.tag(2)
        }
        .fullScreenCover(isPresented: .init(get: { !walkthroughDone }, set: { walkthroughDone = !$0 })) {
            WalkthroughView { walkthroughDone = true }
                .environmentObject(engine)
        }
        .onChange(of: router.pending) { _, action in
            guard let action else { return }
            switch action {
            case .start: engine.start(); router.selectedTab = 1
            case .stop: engine.stop(); router.selectedTab = 1
            case .classes: router.selectedTab = 0
            case .bookings: router.selectedTab = 1
            }
            router.pending = nil
        }
    }
}
