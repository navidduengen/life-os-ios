import XCTest
@testable import LifeOSKit

final class HealthImportTests: XCTestCase {
    func testCatalogCoversEveryGroupWithUniqueIdentifiers() {
        let ids = HealthDataCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertGreaterThan(ids.count, 200)
        XCTAssertEqual(HealthDataCatalog.grouped.map(\.group), HealthDataGroup.ordered)
        XCTAssertEqual(HealthDataCatalog.type("HKQuantityTypeIdentifierStepCount")?.aggregation, .sum)
        XCTAssertEqual(HealthDataCatalog.type("HKQuantityTypeIdentifierHeartRate")?.aggregation, .avg)
        XCTAssertEqual(HealthDataCatalog.type("HKWorkoutTypeIdentifier")?.kind, .workout)
        for type in HealthDataCatalog.all {
            XCTAssertTrue(type.id.hasPrefix("HK"), type.id)
            XCTAssertFalse(type.label.isEmpty, type.id)
        }
    }

    func testSettingsToggleTypesAndGroups() {
        var settings = HealthImportSettings()
        settings.set(.sleep, enabled: true)
        XCTAssertTrue(settings.isEnabled(.sleep))
        XCTAssertTrue(settings.enabledTypes.contains("HKCategoryTypeIdentifierSleepAnalysis"))

        let wristTemperature = HealthDataCatalog.type("HKQuantityTypeIdentifierAppleSleepingWristTemperature")!
        settings.set(wristTemperature, enabled: false)
        XCTAssertFalse(settings.isEnabled(.sleep))
        XCTAssertEqual(settings.selectedTypes.map(\.group), Array(repeating: .sleep, count: settings.enabledTypes.count))

        let store = HealthImportSettingsStore(defaults: UserDefaults(suiteName: "HealthImportTests-\(UUID().uuidString)")!)
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testBatchesAreChunkedToTheServerLimit() {
        let now = Date()
        let samples = (0..<1_203).map { HealthSamplePayload(externalId: "\($0)", type: "HKQuantityTypeIdentifierStepCount", kind: .quantity, value: 1, unit: "count", startAt: now, endAt: now) }
        let chunks = HealthImportBatch(samples: samples, deleted: ["a", "b"]).chunked()
        XCTAssertEqual(chunks.map(\.samples.count), [500, 500, 203])
        XCTAssertEqual(chunks.map(\.deleted.count), [2, 0, 0])
        XCTAssertTrue(HealthImportBatch().chunked().isEmpty)
    }

    func testPayloadEncodesSnakeCaseAndKeepsMetadataKeys() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let sample = HealthSamplePayload(
            externalId: "6F1C", type: "HKQuantityTypeIdentifierHeartRate", kind: .quantity, value: 62, unit: "count/min",
            startAt: start, endAt: start, sourceName: "Apple Watch",
            metadata: HealthMetadata.json(["HKMetadataKeyHeartRateMotionContext": 1, "HKWasUserEntered": true])
        )
        let data = try LifeOSJSON.makeEncoder().encode(HealthImportBatch(samples: [sample]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try XCTUnwrap((object["samples"] as? [[String: Any]])?.first)
        XCTAssertEqual(first["external_id"] as? String, "6F1C")
        XCTAssertEqual(first["source_name"] as? String, "Apple Watch")
        XCTAssertEqual(first["start_at"] as? String, "2026-09-21T14:13:20Z")
        let metadata = try XCTUnwrap(first["metadata"] as? [String: Any])
        XCTAssertEqual(Set(metadata.keys), ["heart_rate_motion_context", "was_user_entered"])
    }

    func testMetadataKeyConversion() {
        XCTAssertEqual(HealthMetadata.key("HKMetadataKeyHeartRateMotionContext"), "heart_rate_motion_context")
        XCTAssertEqual(HealthMetadata.key("HKWasUserEntered"), "was_user_entered")
        XCTAssertEqual(HealthMetadata.key("com.example.custom-key"), "com_example_custom_key")
    }

    func testDemoServiceUpsertsAndDeletes() async throws {
        let demo = DemoService()
        let now = Date()
        let sample = HealthSamplePayload(externalId: "x", type: "HKQuantityTypeIdentifierStepCount", kind: .quantity, value: 10, unit: "count", startAt: now, endAt: now)
        _ = try await demo.importHealth(HealthImportBatch(samples: [sample, sample]))
        let result = try await demo.importHealth(HealthImportBatch(deleted: ["x", "unknown"]))
        XCTAssertEqual(result.deleted, 1)
        let removed = try await demo.deleteImportedHealth(type: nil)
        XCTAssertEqual(removed, 0)
    }
}

final class HealthMetadataValueTests: XCTestCase {
    func testKeepsBooleansIntegersAndDoublesApart() {
        XCTAssertEqual(HealthMetadata.json(NSNumber(value: true)), .bool(true))
        XCTAssertEqual(HealthMetadata.json(NSNumber(value: 1)), .int(1))
        XCTAssertEqual(HealthMetadata.json(NSNumber(value: 1.5)), .number(1.5))
        XCTAssertEqual(HealthMetadata.json("x"), .string("x"))
    }
}
