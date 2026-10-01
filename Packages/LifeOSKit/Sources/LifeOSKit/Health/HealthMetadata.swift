import Foundation

public enum HealthMetadata {
    /// `HKMetadataKeyHeartRateMotionContext` → `heart_rate_motion_context`.
    /// Keys go out already in snake_case, because the API encoder converts
    /// dictionary keys too and would otherwise mangle them.
    public static func key(_ raw: String) -> String {
        var name = raw
        for prefix in ["HKMetadataKey", "HK"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            break
        }
        var result = ""
        var previousWasLower = false
        for character in name {
            if character.isUppercase {
                if previousWasLower { result.append("_") }
                result.append(contentsOf: character.lowercased())
                previousWasLower = false
            } else if character.isLetter || character.isNumber {
                result.append(character)
                previousWasLower = true
            } else {
                if !result.hasSuffix("_") { result.append("_") }
                previousWasLower = false
            }
        }
        return result
    }

    /// Converts HealthKit metadata values (strings, numbers, dates, booleans)
    /// into JSON. Anything else is described as text.
    public static func json(_ value: Any) -> JSONValue {
        switch value {
        case let number as NSNumber:
            // HealthKit hands out NSNumber; tell booleans and integers apart
            // instead of letting `as? Bool` turn every 1 into true.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if CFNumberIsFloatType(number) { return .number(number.doubleValue) }
            return .int(number.intValue)
        case let string as String: return .string(string)
        case let date as Date: return .string(iso.string(from: date))
        default: return .string(String(describing: value))
        }
    }

    public static func json(_ metadata: [String: Any]?) -> [String: JSONValue]? {
        guard let metadata, !metadata.isEmpty else { return nil }
        var result: [String: JSONValue] = [:]
        for (rawKey, value) in metadata {
            result[key(rawKey)] = json(value)
        }
        return result
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
