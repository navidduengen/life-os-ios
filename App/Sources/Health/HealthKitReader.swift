#if canImport(HealthKit) && !targetEnvironment(macCatalyst)
import Foundation
import HealthKit
import LifeOSKit

/// Reads Apple Health through HealthKit and turns samples into API payloads.
/// Only reads; the app never writes to Apple Health.
final class HealthKitReader: @unchecked Sendable {
    let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Types

    /// The HealthKit object type for a catalog entry, or nil when this iOS
    /// version does not know it (e.g. iOS 18 types on iOS 17).
    func objectType(for type: HealthDataType) -> HKObjectType? {
        switch type.kind {
        case .quantity:
            return HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: type.id))
        case .category:
            return HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: type.id))
        case .workout:
            return HKObjectType.workoutType()
        case .ecg:
            return HKObjectType.electrocardiogramType()
        case .audiogram:
            return HKObjectType.audiogramSampleType()
        case .stateOfMind:
            if #available(iOS 18.0, *) { return HKObjectType.stateOfMindType() }
            return nil
        case .clinical:
            return HKObjectType.clinicalType(forIdentifier: HKClinicalTypeIdentifier(rawValue: type.id))
        case .characteristic:
            return HKObjectType.characteristicType(forIdentifier: HKCharacteristicTypeIdentifier(rawValue: type.id))
        }
    }

    /// Catalog entries this device can read.
    func supportedTypes() -> [HealthDataType] {
        HealthDataCatalog.all.filter { objectType(for: $0) != nil }
    }

    func requestAuthorization(for types: [HealthDataType]) async throws {
        let objectTypes = Set(types.compactMap(objectType(for:)))
        guard !objectTypes.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: objectTypes)
    }

    // MARK: - Anchored reads

    struct Page {
        var payloads: [HealthSamplePayload]
        var deleted: [String]
        var anchor: HKQueryAnchor?
        /// More results are waiting behind this page.
        var hasMore: Bool
    }

    /// One page of new and deleted samples since `anchor`. HealthKit returns
    /// at most `limit` objects, so large histories (heart rate) arrive in pages.
    func page(for type: HealthDataType, anchor: HKQueryAnchor?, since start: Date?, units: [HKQuantityType: HKUnit], limit: Int = 2_000) async throws -> Page {
        guard let sampleType = objectType(for: type) as? HKSampleType else {
            return Page(payloads: [], deleted: [], anchor: anchor, hasMore: false)
        }
        // The start date only limits the very first import; later pages follow the anchor.
        let predicate = anchor == nil ? start.map { HKQuery.predicateForSamples(withStart: $0, end: nil) } : nil

        let (samples, deleted, newAnchor): ([HKSample], [HKDeletedObject], HKQueryAnchor?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: predicate, anchor: anchor, limit: limit) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? [], deleted ?? [], newAnchor))
                }
            }
            store.execute(query)
        }

        var payloads: [HealthSamplePayload] = []
        payloads.reserveCapacity(samples.count)
        for sample in samples {
            if let payload = await payload(for: sample, type: type, units: units) { payloads.append(payload) }
        }
        return Page(
            payloads: payloads,
            deleted: deleted.map { $0.uuid.uuidString },
            anchor: newAnchor,
            hasMore: samples.count + deleted.count >= limit
        )
    }

    /// The user's preferred units (kg vs lb, °C vs °F) for the quantity types.
    func preferredUnits(for types: [HealthDataType]) async -> [HKQuantityType: HKUnit] {
        let quantityTypes = Set(types.compactMap { objectType(for: $0) as? HKQuantityType })
        guard !quantityTypes.isEmpty else { return [:] }
        return (try? await store.preferredUnits(for: quantityTypes)) ?? [:]
    }

    // MARK: - Characteristics

    /// Characteristics (birthday, blood type, …) have no history; they are
    /// sent as one record each with a stable id.
    func characteristic(_ type: HealthDataType) -> HealthSamplePayload? {
        let now = Date()
        func payload(value: Double? = nil, text: String?) -> HealthSamplePayload? {
            guard value != nil || text != nil else { return nil }
            return HealthSamplePayload(externalId: "characteristic.\(type.id)", type: type.id, kind: .characteristic, value: value, valueText: text, startAt: now, endAt: now)
        }
        switch type.id {
        case HKCharacteristicTypeIdentifier.dateOfBirth.rawValue:
            guard let components = try? store.dateOfBirthComponents(), let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
            return payload(text: HealthLabels.localDate(date))
        case HKCharacteristicTypeIdentifier.biologicalSex.rawValue:
            guard let sex = try? store.biologicalSex().biologicalSex, sex != .notSet else { return nil }
            return payload(value: Double(sex.rawValue), text: HealthLabels.biologicalSex(sex))
        case HKCharacteristicTypeIdentifier.bloodType.rawValue:
            guard let blood = try? store.bloodType().bloodType, blood != .notSet else { return nil }
            return payload(value: Double(blood.rawValue), text: HealthLabels.bloodType(blood))
        case HKCharacteristicTypeIdentifier.fitzpatrickSkinType.rawValue:
            guard let skin = try? store.fitzpatrickSkinType().skinType, skin != .notSet else { return nil }
            return payload(value: Double(skin.rawValue), text: "Typ \(skin.rawValue)")
        case HKCharacteristicTypeIdentifier.wheelchairUse.rawValue:
            guard let use = try? store.wheelchairUse().wheelchairUse, use != .notSet else { return nil }
            return payload(value: Double(use.rawValue), text: use == .yes ? "Ja" : "Nein")
        case HKCharacteristicTypeIdentifier.activityMoveMode.rawValue:
            guard let mode = try? store.activityMoveMode().activityMoveMode else { return nil }
            return payload(value: Double(mode.rawValue), text: mode == .appleMoveTime ? "Bewegungsminuten" : "Aktive Kalorien")
        default:
            return nil
        }
    }

    // MARK: - Sample → payload

    private func payload(for sample: HKSample, type: HealthDataType, units: [HKQuantityType: HKUnit]) async -> HealthSamplePayload? {
        var payload = HealthSamplePayload(
            externalId: sample.uuid.uuidString,
            type: type.id,
            kind: type.kind,
            startAt: sample.startDate,
            endAt: sample.endDate,
            sourceName: sample.sourceRevision.source.name,
            deviceName: sample.device?.name ?? sample.device?.model,
            metadata: HealthMetadata.json(sample.metadata)
        )

        switch sample {
        case let quantity as HKQuantitySample:
            guard let unit = units[quantity.quantityType] ?? Self.fallbackUnit(for: quantity.quantityType),
                  quantity.quantity.is(compatibleWith: unit)
            else { return nil }
            payload.value = quantity.quantity.doubleValue(for: unit)
            payload.unit = unit.unitString

        case let category as HKCategorySample:
            payload.value = Double(category.value)
            payload.valueText = HealthLabels.categoryValue(category.value, type: type.id)
            payload.unit = "min"
            // Duration is what matters for sleep and mindfulness.
            payload.metadata = merge(payload.metadata, ["duration_minutes": .number(category.endDate.timeIntervalSince(category.startDate) / 60)])

        case let workout as HKWorkout:
            payload.value = workout.duration / 60
            payload.unit = "min"
            payload.valueText = HealthLabels.workoutActivity(workout.workoutActivityType)
            var extra: [String: JSONValue] = ["activity_type": .int(Int(workout.workoutActivityType.rawValue))]
            if let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                extra["active_energy_kcal"] = .number(kcal)
            }
            for distanceType in [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming, .distanceWheelchair, .distanceDownhillSnowSports] {
                if let meters = workout.statistics(for: HKQuantityType(distanceType))?.sumQuantity()?.doubleValue(for: .meter()) {
                    extra["distance_m"] = .number(meters)
                    break
                }
            }
            let bpm = HKUnit.count().unitDivided(by: .minute())
            if let heartRate = workout.statistics(for: HKQuantityType(.heartRate)) {
                if let average = heartRate.averageQuantity()?.doubleValue(for: bpm) { extra["heart_rate_avg"] = .number(average) }
                if let maximum = heartRate.maximumQuantity()?.doubleValue(for: bpm) { extra["heart_rate_max"] = .number(maximum) }
            }
            payload.metadata = merge(payload.metadata, extra)

        case let ecg as HKElectrocardiogram:
            payload.value = ecg.averageHeartRate?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            payload.unit = "count/min"
            payload.valueText = HealthLabels.ecgClassification(ecg.classification)
            payload.metadata = merge(payload.metadata, [
                "classification": .int(ecg.classification.rawValue),
                "symptoms_status": .int(ecg.symptomsStatus.rawValue),
                "voltage_measurements": .int(ecg.numberOfVoltageMeasurements),
            ])

        case let audiogram as HKAudiogramSample:
            let dbHL = HKUnit.decibelHearingLevel()
            let points: [JSONValue] = audiogram.sensitivityPoints.map { point in
                var entry: [String: JSONValue] = ["frequency_hz": .number(point.frequency.doubleValue(for: .hertz()))]
                if let left = point.leftEarSensitivity?.doubleValue(for: dbHL) { entry["left_db_hl"] = .number(left) }
                if let right = point.rightEarSensitivity?.doubleValue(for: dbHL) { entry["right_db_hl"] = .number(right) }
                return .object(entry)
            }
            payload.value = Double(points.count)
            payload.unit = "points"
            payload.metadata = merge(payload.metadata, ["sensitivity_points": .array(points)])

        case let record as HKClinicalRecord:
            payload.valueText = record.displayName
            var extra: [String: JSONValue] = [:]
            if let fhir = record.fhirResource {
                extra["fhir_resource_type"] = .string(fhir.resourceType.rawValue)
                extra["fhir_identifier"] = .string(fhir.identifier)
                // Raw FHIR JSON stays a string so the API encoder leaves its keys alone.
                extra["fhir_json"] = .string(String(decoding: fhir.data, as: UTF8.self))
            }
            payload.metadata = merge(payload.metadata, extra)

        default:
            if #available(iOS 18.0, *), let mood = sample as? HKStateOfMind {
                payload.value = mood.valence
                payload.valueText = mood.kind == .dailyMood ? "Tagesstimmung" : "Momentane Emotion"
                payload.metadata = merge(payload.metadata, [
                    "kind": .int(mood.kind.rawValue),
                    "valence_classification": .int(mood.valenceClassification.rawValue),
                    "labels": .array(mood.labels.map { .int($0.rawValue) }),
                    "associations": .array(mood.associations.map { .int($0.rawValue) }),
                ])
            } else {
                return nil
            }
        }
        return payload
    }

    private func merge(_ base: [String: JSONValue]?, _ extra: [String: JSONValue]) -> [String: JSONValue] {
        (base ?? [:]).merging(extra) { _, new in new }
    }

    /// Used only when HealthKit reports no preferred unit.
    private static func fallbackUnit(for type: HKQuantityType) -> HKUnit? {
        let candidates: [HKUnit] = [
            .count(), .meter(), .kilocalorie(), .gramUnit(with: .kilo), .percent(), .degreeCelsius(),
            .millimeterOfMercury(), .count().unitDivided(by: .minute()), .secondUnit(with: .milli), .minute(),
            .meter().unitDivided(by: .second()), .watt(), .liter(), .gram(), .decibelAWeightedSoundPressureLevel(),
        ]
        return candidates.first { type.is(compatibleWith: $0) }
    }
}
#endif
