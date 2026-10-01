import LifeOSKit
import SwiftUI

/// Load state for a screen: spinner, content, or an error with retry.
enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

struct AsyncContent<Value, Content: View>: View {
    let state: Loadable<Value>
    let retry: () async -> Void
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(value):
            content(value)
        case let .failed(message):
            ContentUnavailableView {
                Label("Konnte nicht laden", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Erneut versuchen") { Task { await retry() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension Error {
    var userMessage: String {
        (self as? APIError)?.message ?? localizedDescription
    }
}

enum Formatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM"
        return f
    }()

    private static let localDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// `Y-m-d` from the API → date at local midnight.
    static func date(fromLocal value: String) -> Date? { localDate.date(from: value) }
    static func local(_ date: Date) -> String { localDate.string(from: date) }

    /// "Heute", "Morgen", "Gestern" or "3. Okt.".
    static func relativeDay(_ value: String) -> String {
        guard let date = date(fromLocal: value) else { return value }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        return shortDate.string(from: date)
    }
}
