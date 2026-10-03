import SwiftUI

/// Miniatura della lezione (immagine mywellness).
struct ClassThumb: View {
    let url: String?
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let u = url, let url = URL(string: u) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
            } else {
                ZStack { Color.secondary.opacity(0.12); Image(systemName: "figure.strengthtraining.functional").foregroundStyle(.secondary) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Selettore del profilo mywellness (modalità server).
struct ProfileMenu: View {
    @EnvironmentObject var engine: BookingEngine
    var body: some View {
        Menu {
            ForEach(engine.profiles) { p in
                Button { engine.selectProfile(p.id) } label: {
                    if p.id == engine.selectedProfile?.id { Label(p.label, systemImage: "checkmark") } else { Text(p.label) }
                }
            }
        } label: {
            Label(engine.selectedProfile?.label ?? "Profilo", systemImage: "person.crop.circle")
        }
    }
}
