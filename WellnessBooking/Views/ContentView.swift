import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: BookingEngine
    @AppStorage("walkthroughDone") private var walkthroughDone = false

    var body: some View {
        TabView {
            NavigationStack { ClassesView() }
                .tabItem { Label("Lezioni", systemImage: "calendar") }
            NavigationStack { WatchListView() }
                .tabItem { Label("Prenotazioni", systemImage: "checkmark.circle") }
                .badge(engine.items.filter { !$0.state.isTerminal }.count)
            NavigationStack { MoreView() }
                .tabItem { Label("Altro", systemImage: "ellipsis.circle") }
        }
        .fullScreenCover(isPresented: .init(get: { !walkthroughDone }, set: { walkthroughDone = !$0 })) {
            WalkthroughView { walkthroughDone = true }
                .environmentObject(engine)
        }
    }
}
