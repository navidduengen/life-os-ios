import Foundation

/// How a type is stored in Apple Health, which decides how the app reads it.
public enum HealthDataKind: String, Codable, Sendable {
    case quantity, category, workout, ecg, audiogram, stateOfMind, clinical, characteristic
}

/// How daily values of a type combine: summed (steps, kcal), averaged
/// (heart rate, weight) or counted (events, sleep stages, records).
public enum HealthAggregation: String, Codable, Sendable {
    case sum, avg, count
}

public enum HealthDataGroup: String, Codable, CaseIterable, Sendable {
    case activity, body, heart, vitals, respiratory, mobility, nutrition, sleep, mind
    case hearing, environment, cycle, symptoms, habits, workouts, records, profile
}

/// One Apple Health data type the app can import. `id` is the HealthKit
/// identifier raw value (`HKQuantityTypeIdentifierStepCount`), which is also
/// what the server stores as `type`.
public struct HealthDataType: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: HealthDataKind
    public let group: HealthDataGroup
    public let label: String
    public let aggregation: HealthAggregation

    /// Health records need their own Apple entitlement and permission sheet.
    public var isClinicalRecord: Bool { kind == .clinical }
}

/// Every Apple Health type the app knows. Types the running iOS version does
/// not support are filtered out at runtime by the HealthKit reader.
public enum HealthDataCatalog {
    public static func type(_ id: String) -> HealthDataType? {
        byID[id]
    }

    public static func types(in group: HealthDataGroup) -> [HealthDataType] {
        all.filter { $0.group == group }
    }

    /// Groups in display order, each with its types.
    public static var grouped: [(group: HealthDataGroup, types: [HealthDataType])] {
        HealthDataGroup.ordered.compactMap { group in
            let types = types(in: group)
            return types.isEmpty ? nil : (group: group, types: types)
        }
    }

    private static let byID: [String: HealthDataType] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
