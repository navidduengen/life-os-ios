import Foundation
import LifeOSKit
import Observation
#if canImport(HealthKit) && !targetEnvironment(macCatalyst)
import HealthKit
#endif

/// Drives the Apple Health import: permissions, the user's type selection,
/// incremental sync with anchors, and background delivery.
@MainActor
@Observable
final class HealthSyncManager {
    enum State: Equatable {
        case idle
        case syncing(done: Int, total: Int)
        case failed(String)
    }

    private(set) var settings: HealthImportSettings
    private(set) var state: State = .idle
    private(set) var lastResult: String?
    /// Catalog entries this device can read (empty on Mac and without Health).
    private(set) var supportedTypes: [HealthDataType] = []

    @ObservationIgnored private let settingsStore = HealthImportSettingsStore()
    /// Set by `AppModel`; returns the backend the user is signed in to.
    @ObservationIgnored var serviceProvider: () -> LifeOSService = { DemoService() }
    #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
    @ObservationIgnored private let reader = HealthKitReader()
    @ObservationIgnored private let anchors = HealthAnchorStore()
    @ObservationIgnored private var observers: [HKObserverQuery] = []
    #endif

    init() {
        self.settings = settingsStore.load()
        #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
        if HealthKitReader.isAvailable { supportedTypes = reader.supportedTypes() }
        #endif
    }

    var isAvailable: Bool { !supportedTypes.isEmpty }
    var isSyncing: Bool {
        if case .syncing = state { return true }
        return false
    }

    func supportedTypes(in group: HealthDataGroup) -> [HealthDataType] {
        supportedTypes.filter { $0.group == group }
    }

    // MARK: - Settings

    func update(_ change: (inout HealthImportSettings) -> Void) {
        let before = settings
        change(&settings)
        settings.enabledTypes.formIntersection(Set(supportedTypes.map(\.id)))
        settingsStore.save(settings)
        if before.enabledTypes != settings.enabledTypes || before.isEnabled != settings.isEnabled || before.backgroundSync != settings.backgroundSync {
            Task { await refreshBackgroundDelivery() }
        }
    }

    func setEnabled(_ type: HealthDataType, _ enabled: Bool) { update { $0.set(type, enabled: enabled) } }

    func setEnabled(_ group: HealthDataGroup, _ enabled: Bool) {
        update { settings in
            for type in supportedTypes(in: group) { settings.set(type, enabled: enabled) }
        }
    }

    func isEnabled(_ group: HealthDataGroup) -> Bool {
        let types = supportedTypes(in: group)
        return !types.isEmpty && types.allSatisfy { settings.enabledTypes.contains($0.id) }
    }

    func enableAll(_ enabled: Bool) {
        update { settings in
            settings.enabledTypes = enabled ? Set(supportedTypes.map(\.id)) : []
        }
    }

    // MARK: - Sync

    /// Asks for read access to the selected types, then imports.
    func authorizeAndSync() async {
        #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
        do {
            try await reader.requestAuthorization(for: settings.selectedTypes)
        } catch {
            state = .failed("Apple Health hat den Zugriff nicht freigegeben: \(error.localizedDescription)")
            return
        }
        await sync()
        #endif
    }

    /// Imports everything new since the last sync for each selected type.
    /// Anchors move forward only after the server accepted the batch, so an
    /// interrupted sync resumes where it stopped.
    func sync(only typeIDs: Set<String>? = nil) async {
        #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
        guard settings.isEnabled, !isSyncing else { return }
        let types = settings.selectedTypes.filter { typeIDs?.contains($0.id) ?? true }
        guard !types.isEmpty else { return }

        state = .syncing(done: 0, total: types.count)
        let service = serviceProvider()
        let units = await reader.preferredUnits(for: types)
        let start = settings.initialRange.startDate()
        var imported = 0
        var deleted = 0

        do {
            for (index, type) in types.enumerated() {
                if type.kind == .characteristic {
                    if let payload = reader.characteristic(type) {
                        imported += try await service.importHealth(HealthImportBatch(samples: [payload])).imported
                    }
                } else {
                    var anchor = anchors.anchor(for: type.id)
                    var hasMore = true
                    while hasMore {
                        let page = try await reader.page(for: type, anchor: anchor, since: start, units: units)
                        for batch in HealthImportBatch(samples: page.payloads, deleted: page.deleted).chunked() {
                            let result = try await service.importHealth(batch)
                            imported += result.imported
                            deleted += result.deleted
                        }
                        anchor = page.anchor
                        anchors.save(page.anchor, for: type.id)
                        hasMore = page.hasMore
                    }
                }
                state = .syncing(done: index + 1, total: types.count)
            }
            update { $0.lastSyncAt = Date() }
            lastResult = "\(imported.formatted()) Einträge übertragen" + (deleted > 0 ? ", \(deleted.formatted()) gelöscht" : "")
            state = .idle
        } catch let error as APIError {
            state = .failed(error.message)
        } catch {
            state = .failed("Abgleich fehlgeschlagen: \(error.localizedDescription)")
        }
        #endif
    }

    /// Deletes imported data on the server and forgets the anchors, so the
    /// next sync imports again from the chosen start date.
    func deleteServerData() async {
        do {
            let count = try await serviceProvider().deleteImportedHealth(type: nil)
            #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
            anchors.reset()
            #endif
            update { $0.lastSyncAt = nil }
            lastResult = "\(count.formatted()) Einträge auf dem Server gelöscht"
            state = .idle
        } catch {
            state = .failed(error.userMessage)
        }
    }

    /// Called when the account changes: the next account starts fresh.
    func resetForNewAccount() {
        #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
        anchors.reset()
        #endif
        update { $0.lastSyncAt = nil }
        lastResult = nil
    }

    // MARK: - Background delivery

    /// Registers observer queries and background delivery for the selected
    /// types. iOS wakes the app when new samples arrive (at most hourly).
    func refreshBackgroundDelivery() async {
        #if canImport(HealthKit) && !targetEnvironment(macCatalyst)
        guard HealthKitReader.isAvailable else { return }
        for query in observers { reader.store.stop(query) }
        observers = []
        try? await reader.store.disableAllBackgroundDelivery()

        guard settings.isEnabled, settings.backgroundSync else { return }
        for type in settings.selectedTypes where type.kind != .characteristic {
            guard let sampleType = reader.objectType(for: type) as? HKSampleType else { continue }
            let typeID = type.id
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await self?.sync(only: [typeID])
                    completion()
                }
            }
            reader.store.execute(query)
            observers.append(query)
            try? await reader.store.enableBackgroundDelivery(for: sampleType, frequency: .hourly)
        }
        #endif
    }
}

#if canImport(HealthKit) && !targetEnvironment(macCatalyst)
/// Remembers per type how far the import got (HealthKit query anchors).
final class HealthAnchorStore {
    private let defaults = UserDefaults.standard
    private let prefix = "healthAnchor."

    func anchor(for typeID: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: prefix + typeID) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func save(_ anchor: HKQueryAnchor?, for typeID: String) {
        guard let anchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: prefix + typeID)
    }

    func reset() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
#endif
