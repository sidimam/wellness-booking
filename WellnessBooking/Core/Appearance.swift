import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Colore app / icona alternativa (stesso schema di aMule Remote e Unraid Drive).
struct AppIconColor: Identifiable, Equatable {
    let key: String
    let label: String
    let tint: Color
    var id: String { key }

    static let all: [AppIconColor] = [
        .init(key: "teal",      label: "Verde acqua (originale)", tint: Color(red: 0.05, green: 0.64, blue: 0.65)),
        .init(key: "blu",       label: "Blu",       tint: Color(red: 0.18, green: 0.44, blue: 0.89)),
        .init(key: "verde",     label: "Verde",     tint: Color(red: 0.24, green: 0.62, blue: 0.34)),
        .init(key: "arancione", label: "Arancione", tint: Color(red: 0.91, green: 0.35, blue: 0.05)),
        .init(key: "viola",     label: "Viola",     tint: Color(red: 0.49, green: 0.30, blue: 0.88)),
        .init(key: "rosso",     label: "Rosso",     tint: Color(red: 0.84, green: 0.27, blue: 0.25)),
        .init(key: "grafite",   label: "Grafite",   tint: Color(red: 0.35, green: 0.40, blue: 0.45)),
    ]

    static func tint(for key: String) -> Color { all.first { $0.key == key }?.tint ?? all[0].tint }

    static func apply(_ key: String) {
        #if os(iOS)
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else { return }
            let name = key == "teal" ? nil : "AppIcon-\(key)"
            if UIApplication.shared.alternateIconName != name { UIApplication.shared.setAlternateIconName(name) }
        }
        #endif
    }
}

struct IconColorPicker: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppIconColor.all) { c in
                Button { selection = c.key } label: {
                    ZStack {
                        Circle().fill(c.tint).frame(width: 30, height: 30)
                        if selection == c.key {
                            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(c.label))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: "Sistema"; case .light: "Chiaro"; case .dark: "Scuro" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

func appVersionString() -> String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    return "\(v) (build \(b))"
}
