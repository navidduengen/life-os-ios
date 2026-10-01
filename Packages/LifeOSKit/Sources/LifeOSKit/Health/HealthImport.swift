import Foundation

/// One Apple Health record as sent to `POST /api/v1/health/apple-health/import`.
public struct HealthSamplePayload: Encodable, Equatable, Sendable {
    /// HealthKit UUID; the server upserts on it, so a resent sample is not duplicated.
    public var externalId: String
    public var type: String
    public var kind: HealthDataKind
    public var value: Double?
    public var unit: String?
    public var valueText: String?
    public var startAt: Date
    public var endAt: Date
    public var sourceName: String?
    public var deviceName: String?
    public var metadata: [String: JSONValue]?

    public init(
        externalId: String, type: String, kind: HealthDataKind, value: Double? = nil, unit: String? = nil,
        valueText: String? = nil, startAt: Date, endAt: Date, sourceName: String? = nil, deviceName: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.externalId = externalId
        self.type = type
        self.kind = kind
        self.value = value
        self.unit = unit
        self.valueText = valueText
        self.startAt = startAt
        self.endAt = endAt
        self.sourceName = sourceName
        self.deviceName = deviceName
        self.metadata = metadata
    }
}

public struct HealthImportBatch: Encodable, Equatable, Sendable {
    public var samples: [HealthSamplePayload]
    /// HealthKit UUIDs of samples deleted in Apple Health since the last sync.
    public var deleted: [String]

    public init(samples: [HealthSamplePayload] = [], deleted: [String] = []) {
        self.samples = samples
        self.deleted = deleted
    }

    public var isEmpty: Bool { samples.isEmpty && deleted.isEmpty }

    /// The server accepts at most `limit` samples and `limit` deletions per request.
    public static let limit = 500

    /// Splits into requests the server accepts.
    public func chunked(limit: Int = HealthImportBatch.limit) -> [HealthImportBatch] {
        var batches: [HealthImportBatch] = []
        var samples = self.samples[...]
        var deleted = self.deleted[...]
        while !samples.isEmpty || !deleted.isEmpty {
            batches.append(HealthImportBatch(samples: Array(samples.prefix(limit)), deleted: Array(deleted.prefix(limit))))
            samples = samples.dropFirst(limit)
            deleted = deleted.dropFirst(limit)
        }
        return batches
    }
}

public struct HealthImportResult: Decodable, Equatable, Sendable {
    public let imported: Int
    public let deleted: Int

    public init(imported: Int, deleted: Int) {
        self.imported = imported
        self.deleted = deleted
    }
}

/// How far back the first import of a type reaches.
public enum HealthInitialRange: String, Codable, CaseIterable, Sendable {
    case days30, year1, all

    public var label: String {
        switch self {
        case .days30: "Letzte 30 Tage"
        case .year1: "Letztes Jahr"
        case .all: "Alles"
        }
    }

    public func startDate(now: Date = Date()) -> Date? {
        switch self {
        case .days30: Calendar(identifier: .gregorian).date(byAdding: .day, value: -30, to: now)
        case .year1: Calendar(identifier: .gregorian).date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}

/// What the user chose to import. Stored on the device, because HealthKit
/// permissions are per device too.
public struct HealthImportSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var enabledTypes: Set<String>
    public var initialRange: HealthInitialRange
    public var backgroundSync: Bool
    public var lastSyncAt: Date?

    public init(isEnabled: Bool = false, enabledTypes: Set<String> = [], initialRange: HealthInitialRange = .year1, backgroundSync: Bool = true, lastSyncAt: Date? = nil) {
        self.isEnabled = isEnabled
        self.enabledTypes = enabledTypes
        self.initialRange = initialRange
        self.backgroundSync = backgroundSync
        self.lastSyncAt = lastSyncAt
    }

    /// Enabled types that exist in the catalog, in catalog order.
    public var selectedTypes: [HealthDataType] {
        HealthDataCatalog.all.filter { enabledTypes.contains($0.id) }
    }

    public mutating func set(_ type: HealthDataType, enabled: Bool) {
        if enabled { enabledTypes.insert(type.id) } else { enabledTypes.remove(type.id) }
    }

    public mutating func set(_ group: HealthDataGroup, enabled: Bool) {
        for type in HealthDataCatalog.types(in: group) { set(type, enabled: enabled) }
    }

    public func isEnabled(_ group: HealthDataGroup) -> Bool {
        HealthDataCatalog.types(in: group).allSatisfy { enabledTypes.contains($0.id) }
    }
}

public final class HealthImportSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "healthImportSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> HealthImportSettings {
        guard let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(HealthImportSettings.self, from: data) else {
            return HealthImportSettings()
        }
        return settings
    }

    public func save(_ settings: HealthImportSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
