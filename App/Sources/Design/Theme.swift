import LifeOSKit
import SwiftUI

enum Theme {
    /// Study Hub indigo, the Life OS brand colour on the web.
    static let brand = Color(hex: AppModuleStyle.Accent.indigo.hex)

    /// One control height everywhere, like the 44 px scale of the web shell.
    static let controlHeight: CGFloat = 44
    static let corner: CGFloat = 12
    static let spacing: CGFloat = 12
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Parses `#RRGGBB` (module colours from the API).
    init?(hexString: String?) {
        guard let hexString, hexString.hasPrefix("#"), hexString.count == 7,
              let value = UInt32(hexString.dropFirst(), radix: 16)
        else { return nil }
        self.init(hex: value)
    }
}

extension AppModule {
    var style: AppModuleStyle { AppModuleCatalog.style(for: id) }
    var accentColor: Color { Color(hex: style.accent.hex) }
}

/// Rounded icon tile in the app accent, as in the web launcher.
struct AppIconTile: View {
    let module: AppModule
    var size: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(module.accentColor.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: module.style.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .bottomTrailing) {
                if module.sensitivity == .vault {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(size * 0.08)
                        .background(Circle().fill(.black.opacity(0.35)))
                        .offset(x: size * 0.08, y: size * 0.08)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Coloured bar on the leading edge of a card (the "Fächer" look from the web).
struct AccentBar: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .padding(.leading, 6)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            }
    }
}

extension View {
    func accentBar(_ color: Color) -> some View { modifier(AccentBar(color: color)) }
}

extension TaskPriority {
    var color: Color {
        switch self {
        case .low: .secondary
        case .normal: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}
