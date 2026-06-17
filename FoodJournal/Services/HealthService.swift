import Foundation
import HealthKit

// MARK: - HealthService
/// Low-level wrapper around HKHealthStore. Pure HealthKit operations:
/// auth, writes, deletes, reads. No knowledge of the master sync toggle
/// or SwiftData entry mutation — that's HealthSync's job.
@MainActor
enum HealthService {
    static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Types

    /// Every quantity type we ever WRITE. Trans fat omitted — HealthKit has no
    /// dedicated identifier for it. App-side tracking continues independently.
    static var writeQuantityIDs: [HKQuantityTypeIdentifier] {
        [
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
            .dietaryFatSaturated, .dietaryFatPolyunsaturated, .dietaryFatMonounsaturated,
            .dietaryFiber, .dietarySugar,
            .dietaryCholesterol, .dietarySodium, .dietaryPotassium,
            .dietaryCalcium, .dietaryIron, .dietaryMagnesium,
            .dietaryVitaminA, .dietaryVitaminC, .dietaryVitaminD,
            .dietaryWater,
            .bodyMass
        ]
    }

    static var allWriteTypes: Set<HKSampleType> {
        // NOTE: Do NOT include HKCorrelationType(.food). HealthKit explicitly
        // forbids requesting authorization for correlation types — the system
        // crashes with NSInvalidArgumentException at requestAuthorization time.
        // Correlations are saved implicitly when their constituent quantity
        // samples are authorized.
        var set: Set<HKSampleType> = []
        for id in writeQuantityIDs {
            set.insert(HKQuantityType(id))
        }
        return set
    }

    /// Quantity types we ever READ. These are surfaced in the master sync
    /// permission sheet AND requested separately by the v1.9 "Show calories
    /// burned" toggle. Adding new read-only types here is sufficient; the
    /// energy-specific auth helper handles the standalone prompt.
    static var readQuantityIDs: [HKQuantityTypeIdentifier] {
        [.bodyMass, .activeEnergyBurned, .basalEnergyBurned]
    }

    static var allReadTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        for id in readQuantityIDs {
            set.insert(HKQuantityType(id))
        }
        return set
    }

    /// Just the energy read types — used by the v1.9 standalone toggle so we
    /// only prompt for the permissions that toggle actually needs.
    static var energyReadTypes: Set<HKObjectType> {
        [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned)]
    }

    // MARK: Authorization

    /// Shows the iOS HealthKit permission sheet for all our read/write types.
    /// Returns true if the prompt completed and the primary energy type ended
    /// up authorized — used by Settings to decide whether to keep the master
    /// toggle on. Individual per-type denials still result in best-effort writes.
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: allWriteTypes, read: allReadTypes)
            let energy = HKQuantityType(.dietaryEnergyConsumed)
            return store.authorizationStatus(for: energy) == .sharingAuthorized
        } catch {
            return false
        }
    }

    /// Requests READ-only auth for activeEnergyBurned + basalEnergyBurned.
    /// Used by the v1.9 "Show calories burned" toggle. Returns false only
    /// when the call itself errors (HK unavailable, etc.) — HK intentionally
    /// hides read-grant status to protect user privacy, so we cannot tell
    /// here whether the user actually granted. Caller treats "no samples on
    /// a populated day" as "either denied or no data" and displays "—".
    static func requestEnergyReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: energyReadTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: Writes

    /// Writes a food entry to Apple Health as individual quantity samples (one
    /// per nutrient). Returns a JSON-encoded `{typeIdentifierRawValue: uuidString}`
    /// dict on success, nil if nothing could be written. Stored on
    /// FoodEntry.healthSampleID so we can delete each sample later.
    ///
    /// We deliberately do NOT use HKCorrelation here, even though it would
    /// group nicely in the Health "Show All Data" view. The reason: HealthKit
    /// forbids requesting authorization for HKCorrelationType, which means
    /// `deleteObjects(of: HKCorrelationType, predicate:)` always fails with
    /// a silent auth denial — the correlation can never be programmatically
    /// removed. Individual quantity-sample deletes only need write auth on
    /// the corresponding dietary type, which we DO have. Health's per-nutrient
    /// summary screens (Calories Consumed / Protein / etc.) are unaffected.
    static func writeFoodEntry(_ entry: FoodEntry) async -> String? {
        guard isAvailable else { return nil }
        let date = entry.loggedAt
        let s = entry.servings
        let metadata: [String: Any] = [HKMetadataKeyFoodType: entry.name]

        let candidates: [(id: HKQuantityTypeIdentifier, value: Double?, unit: HKUnit)] = [
            (.dietaryEnergyConsumed,      entry.calories * s,                       .kilocalorie()),
            (.dietaryProtein,             entry.protein  * s,                       .gram()),
            (.dietaryCarbohydrates,       entry.carbs    * s,                       .gram()),
            (.dietaryFatTotal,            entry.fat      * s,                       .gram()),
            (.dietaryFatSaturated,        entry.saturatedFat.map { $0 * s },        .gram()),
            (.dietaryFatPolyunsaturated,  entry.polyunsaturatedFat.map { $0 * s },  .gram()),
            (.dietaryFatMonounsaturated,  entry.monounsaturatedFat.map { $0 * s },  .gram()),
            (.dietaryFiber,               entry.fiber.map { $0 * s },               .gram()),
            (.dietarySugar,               entry.sugar.map { $0 * s },               .gram()),
            (.dietaryCholesterol,         entry.cholesterol.map { $0 * s },         .gramUnit(with: .milli)),
            (.dietarySodium,              entry.sodium.map { $0 * s },              .gramUnit(with: .milli)),
            (.dietaryPotassium,           entry.potassium.map { $0 * s },           .gramUnit(with: .milli)),
            (.dietaryCalcium,             entry.calcium.map { $0 * s },             .gramUnit(with: .milli)),
            (.dietaryIron,                entry.iron.map { $0 * s },                .gramUnit(with: .milli)),
            (.dietaryMagnesium,           entry.magnesium.map { $0 * s },           .gramUnit(with: .milli)),
            (.dietaryVitaminA,            entry.vitaminA.map { $0 * s },            .gramUnit(with: .micro)),
            (.dietaryVitaminC,            entry.vitaminC.map { $0 * s },            .gramUnit(with: .milli)),
            (.dietaryVitaminD,            entry.vitaminD.map { $0 * s },            .gramUnit(with: .micro)),
        ]

        var idMap: [String: String] = [:]
        for c in candidates {
            guard let v = c.value, v != 0 else { continue }
            let type = HKQuantityType(c.id)
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { continue }
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: c.unit, doubleValue: v),
                start: date,
                end: date,
                metadata: metadata
            )
            do {
                try await store.save(sample)
                idMap[c.id.rawValue] = sample.uuid.uuidString
            } catch {
                // best-effort: skip this nutrient, continue with the others
            }
        }
        guard !idMap.isEmpty else { return nil }

        let data = (try? JSONSerialization.data(withJSONObject: idMap)) ?? Data()
        return String(data: data, encoding: .utf8)
    }

    static func writeWaterEntry(_ entry: WaterEntry) async -> String? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(.dietaryWater)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return nil }
        let s = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .fluidOunceUS(), doubleValue: entry.amountOz),
            start: entry.loggedAt,
            end: entry.loggedAt
        )
        do {
            try await store.save(s)
            return s.uuid.uuidString
        } catch {
            return nil
        }
    }

    static func writeWeightEntry(_ entry: WeightEntry) async -> String? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(.bodyMass)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else { return nil }
        let s = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .pound(), doubleValue: entry.weightLbs),
            start: entry.loggedAt,
            end: entry.loggedAt
        )
        do {
            try await store.save(s)
            return s.uuid.uuidString
        } catch {
            return nil
        }
    }

    // MARK: Deletes

    private static func deleteByUUID(_ uuidString: String, type: HKObjectType) async {
        guard let uuid = UUID(uuidString: uuidString), isAvailable else { return }
        let predicate = HKQuery.predicateForObject(with: uuid)
        do {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        } catch {
            // silent — write may have been revoked, or sample already gone
        }
    }

    /// Deletes the individual quantity samples that make up a food entry.
    /// `payload` is the JSON-encoded map returned by writeFoodEntry —
    /// `{typeIdentifierRawValue: uuidString}` — so we know which sample type
    /// each UUID belongs to and can route the delete to the right table.
    ///
    /// Legacy payloads from v1.8.2's first cut (a bare correlation UUID, no JSON)
    /// can't be deleted programmatically because correlation-type writes aren't
    /// authorizable. Those orphans need manual cleanup in the Health app.
    static func deleteFoodSamples(payload: String) async {
        guard isAvailable else { return }
        guard let data = payload.data(using: .utf8),
              let idMap = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
        else { return }
        for (typeIDRaw, uuidStr) in idMap {
            guard let uuid = UUID(uuidString: uuidStr) else { continue }
            let typeID = HKQuantityTypeIdentifier(rawValue: typeIDRaw)
            let type = HKQuantityType(typeID)
            let predicate = HKQuery.predicateForObject(with: uuid)
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    static func deleteWaterSample(uuidString: String) async {
        await deleteByUUID(uuidString, type: HKQuantityType(.dietaryWater))
    }

    static func deleteWeightSample(uuidString: String) async {
        await deleteByUUID(uuidString, type: HKQuantityType(.bodyMass))
    }

    // MARK: Reads

    struct ExternalWeight {
        let uuid: String
        let weightLbs: Double
        let date: Date
    }

    // MARK: Energy reads (v1.9 — read-only)

    /// Sums all samples of the given energy type for the calendar day of `date`.
    /// Returns nil if no samples exist OR if the read errors. Nil ≠ 0 here:
    /// a day with no Active Energy data (watch off your wrist) should display
    /// "—", not 0.
    private static func sumEnergyKcal(
        _ id: HKQuantityTypeIdentifier,
        from start: Date,
        to end: Date
    ) async -> Double? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        do {
            let statistics = try await descriptor.result(for: store)
            guard let sum = statistics?.sumQuantity() else { return nil }
            return sum.doubleValue(for: HKUnit.kilocalorie())
        } catch {
            return nil
        }
    }

    static func readActiveEnergy(on date: Date) async -> Double? {
        let (start, end) = dayBounds(of: date)
        return await sumEnergyKcal(.activeEnergyBurned, from: start, to: end)
    }

    static func readBasalEnergy(on date: Date) async -> Double? {
        let (start, end) = dayBounds(of: date)
        return await sumEnergyKcal(.basalEnergyBurned, from: start, to: end)
    }

    /// Parallel fetch of both active and basal energy for a single day. Used
    /// by the Today energy strip — one call site for both queries cuts the
    /// fetch latency roughly in half.
    static func readEnergySummary(on date: Date) async -> (active: Double?, basal: Double?) {
        async let active = readActiveEnergy(on: date)
        async let basal  = readBasalEnergy(on: date)
        return await (active, basal)
    }

    /// Per-day energy sums across a date range. Returns a dict keyed by
    /// start-of-day. Days with no data are absent from the dict — never
    /// present with value 0. Used by TrendsView's Energy averages.
    private static func energyByDay(
        _ id: HKQuantityTypeIdentifier,
        from rangeStart: Date,
        to rangeEnd: Date
    ) async -> [Date: Double] {
        guard isAvailable else { return [:] }
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: rangeStart)
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: rangeEnd, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var result: [Date: Double] = [:]
            collection.enumerateStatistics(from: anchor, to: rangeEnd) { stat, _ in
                if let sum = stat.sumQuantity() {
                    let day = cal.startOfDay(for: stat.startDate)
                    result[day] = sum.doubleValue(for: HKUnit.kilocalorie())
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    static func readActiveEnergy(from: Date, to: Date) async -> [Date: Double] {
        await energyByDay(.activeEnergyBurned, from: from, to: to)
    }

    static func readBasalEnergy(from: Date, to: Date) async -> [Date: Double] {
        await energyByDay(.basalEnergyBurned, from: from, to: to)
    }

    private static func dayBounds(of date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }

    /// Reads all bodyMass samples in Health NOT written by FoodJournal itself
    /// (filtered by source bundle identifier). Used by the "Import weight from
    /// Apple Health" Settings button. Returns sorted newest-first.
    static func readExternalWeightSamples() async -> [ExternalWeight] {
        guard isAvailable else { return [] }
        let ourBundleID = Bundle.main.bundleIdentifier ?? ""
        let type = HKQuantityType(.bodyMass)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            return samples.compactMap { sample in
                guard sample.sourceRevision.source.bundleIdentifier != ourBundleID else { return nil }
                return ExternalWeight(
                    uuid: sample.uuid.uuidString,
                    weightLbs: sample.quantity.doubleValue(for: .pound()),
                    date: sample.startDate
                )
            }
        } catch {
            return []
        }
    }
}

// MARK: - HealthSync
/// Orchestration layer above HealthService. Save/delete paths in the views
/// call into these methods. Reads the master toggle (`healthSyncEnabled` in
/// UserDefaults). Writes are gated on the toggle; deletes are always
/// attempted when the entry has a known healthSampleID, so the user can turn
/// sync off without orphaning Health data they previously wrote.
@MainActor
enum HealthSync {
    /// UserDefaults key matches the @AppStorage("healthSyncEnabled") in Settings.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "healthSyncEnabled")
    }

    // MARK: Save paths

    /// Call from every food save path AFTER context.insert + LibraryFoodUpsert.upsert.
    static func onFoodSaved(_ entry: FoodEntry) {
        guard isEnabled else { return }
        Task { @MainActor in
            if let uuid = await HealthService.writeFoodEntry(entry) {
                entry.healthSampleID = uuid
            }
        }
    }

    static func onWaterSaved(_ entry: WaterEntry) {
        guard isEnabled else { return }
        Task { @MainActor in
            if let uuid = await HealthService.writeWaterEntry(entry) {
                entry.healthSampleID = uuid
            }
        }
    }

    static func onWeightSaved(_ entry: WeightEntry) {
        // Don't write weights that were imported FROM Health back to Health.
        guard isEnabled, !entry.importedFromHealth else { return }
        Task { @MainActor in
            if let uuid = await HealthService.writeWeightEntry(entry) {
                entry.healthSampleID = uuid
            }
        }
    }

    // MARK: Edit path (food only — water and weight have no edit flow)

    /// Call from EditEntrySheet.save AFTER fields are mutated. Deletes the
    /// previous correlation (if any), then writes a fresh one. The delete runs
    /// regardless of master toggle so we don't leave stale samples behind; the
    /// re-write only runs if sync is currently enabled.
    static func onFoodEdited(_ entry: FoodEntry) {
        let oldPayload = entry.healthSampleID
        entry.healthSampleID = nil
        Task { @MainActor in
            if let oldPayload {
                await HealthService.deleteFoodSamples(payload: oldPayload)
            }
            if isEnabled {
                if let newPayload = await HealthService.writeFoodEntry(entry) {
                    entry.healthSampleID = newPayload
                }
            }
        }
    }

    // MARK: Delete paths
    // Call BEFORE context.delete(entry). We capture the UUID, then schedule the
    // Health delete asynchronously. Always runs regardless of master toggle so
    // we clean up orphan samples even if the user turned sync off after writing.

    static func onFoodDeleting(_ entry: FoodEntry) {
        guard let payload = entry.healthSampleID else { return }
        Task { await HealthService.deleteFoodSamples(payload: payload) }
    }

    static func onWaterDeleting(_ entry: WaterEntry) {
        guard let uuid = entry.healthSampleID else { return }
        Task { await HealthService.deleteWaterSample(uuidString: uuid) }
    }

    static func onWeightDeleting(_ entry: WeightEntry) {
        // For entries imported from Health, the Health sample didn't originate
        // here — leave it alone so the user's source-of-truth scale data isn't
        // affected by an in-app delete.
        guard !entry.importedFromHealth, let uuid = entry.healthSampleID else { return }
        Task { await HealthService.deleteWeightSample(uuidString: uuid) }
    }
}
