import Foundation

public enum LifeOSJSON {
    /// Decoder for the Life OS API: snake_case keys and Laravel ISO-8601
    /// timestamps with or without (micro)second fractions.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseTimestamp(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiger Zeitstempel: \(raw)")
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Parses `2026-10-01T08:00:00Z`, `2026-10-01T08:00:00.000000Z` and
    /// `2026-10-01T10:00:00+02:00`. Fractions are truncated to milliseconds,
    /// which is all `ISO8601DateFormatter` accepts.
    public static func parseTimestamp(_ raw: String) -> Date? {
        var value = raw
        if let dot = value.firstIndex(of: ".") {
            let fractionStart = value.index(after: dot)
            let fractionEnd = value[fractionStart...].firstIndex { !$0.isNumber } ?? value.endIndex
            let digits = value[fractionStart..<fractionEnd]
            let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            value = String(value[..<fractionStart]) + millis + String(value[fractionEnd...])
            return fractional.date(from: value)
        }
        return plain.date(from: value)
    }

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
