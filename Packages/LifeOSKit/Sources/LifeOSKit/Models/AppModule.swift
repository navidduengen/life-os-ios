import Foundation

/// `GET /api/v1/app-modules` — one activated app or system module.
/// Icon, accent and order are not part of the API contract; the app maps them
/// from `id` (see `AppModuleCatalog`), mirroring the web `module.json` files.
public struct AppModule: Decodable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Decodable, Sendable { case app, system }
    public enum Sensitivity: String, Decodable, Sendable { case normal, sensitive, vault }

    public let id: String
    public let label: String
    public let description: String
    public let basePath: String
    public let defaultPath: String
    public let kind: Kind
    public let sensitivity: Sensitivity

    public init(id: String, label: String, description: String, basePath: String, defaultPath: String, kind: Kind, sensitivity: Sensitivity) {
        self.id = id
        self.label = label
        self.description = description
        self.basePath = basePath
        self.defaultPath = defaultPath
        self.kind = kind
        self.sensitivity = sensitivity
    }
}

/// Static per-app metadata from the web `module.json` files that the API
/// does not expose.
public struct AppModuleStyle: Equatable, Sendable {
    public let order: Int
    public let symbol: String
    public let accent: Accent
    public let tagline: String?

    public enum Accent: String, Sendable, CaseIterable {
        case indigo, orange, teal, rose, green, violet, slate

        /// `solid` colour from `resources/js/platform/modules/accents.ts`.
        public var hex: UInt32 {
            switch self {
            case .indigo: 0x4F46E5
            case .orange: 0xC2410C
            case .teal: 0x0F766E
            case .rose: 0xBE123C
            case .green: 0x166534
            case .violet: 0x6D28D9
            case .slate: 0x475569
            }
        }
    }
}

public enum AppModuleCatalog {
    public static func style(for id: String) -> AppModuleStyle {
        switch id {
        case "today": AppModuleStyle(order: 0, symbol: "sun.max", accent: .orange, tagline: nil)
        case "inbox": AppModuleStyle(order: 5, symbol: "tray", accent: .slate, tagline: nil)
        case "study": AppModuleStyle(order: 10, symbol: "graduationcap", accent: .indigo, tagline: "Studium & Lernen")
        case "productivity": AppModuleStyle(order: 20, symbol: "checklist", accent: .orange, tagline: "Projekte & To-dos")
        case "calendar": AppModuleStyle(order: 25, symbol: "calendar", accent: .teal, tagline: "Termine & Abos")
        case "health": AppModuleStyle(order: 40, symbol: "heart.text.square", accent: .rose, tagline: "Gesundheit")
        case "finance": AppModuleStyle(order: 50, symbol: "eurosign.circle", accent: .green, tagline: "Finanzen")
        case "journal": AppModuleStyle(order: 60, symbol: "book.closed", accent: .violet, tagline: "Tagebuch")
        default: AppModuleStyle(order: 999, symbol: "square.grid.2x2", accent: .slate, tagline: nil)
        }
    }

    /// Launcher order: by `order`, then label.
    public static func sorted(_ modules: [AppModule]) -> [AppModule] {
        modules.sorted {
            let l = style(for: $0.id).order, r = style(for: $1.id).order
            return l == r ? $0.label < $1.label : l < r
        }
    }
}
