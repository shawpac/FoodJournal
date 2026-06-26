import Foundation
import HealthKit

// MARK: - v2.2 — Read-only Apple Health metrics (sleep + vitals)
//
// Same invariants as v1.9 energy / v2.0 workouts: data is read on demand,
// never cached locally; no @Model storage; no Health writes. Nil ≠ 0 — a
// metric with no samples returns nil and the UI shows "–", never 0. Trends
// skip missing days, never plot 0 or interpolate.
//
// HealthKit read-denial is not detectable per Apple's privacy design: a
// denied type returns no samples — identical to "no data." We do NOT try to
// distinguish; empty is empty.
//
// Architecture is descriptor-driven: every single-value vital is one entry
// in `HealthService.healthMetrics`. Two generic readers (`readMetricToday`,
// `readMetricByDay`) dispatch on the per-metric Aggregation (average / sum /
// latest). Sleep is a category type and BP is a paired correlation, so each
// has its own bespoke reader — but the UI still composes them into the same
// tile layout.

@MainActor
extension HealthService {

    // MARK: - Descriptor for single-value metrics

    /// How to collapse multiple samples in a window down to one number.
    enum MetricAggregation {
        /// Discrete average — for rate-style metrics (heart rate, HRV, SpO2,
        /// resp rate, walking double-support, temp). Summing these is
        /// nonsense.
        case average
        /// Cumulative sum — for counter-style metrics (steps).
        case sum
        /// Most recent sample within the window — for metrics that update
        /// infrequently (VO2 max updates after qualifying workouts; wrist
        /// temperature updates overnight).
        case latest
    }

    struct HealthMetric: Identifiable {
        let identifier: HKQuantityTypeIdentifier
        let displayName: String
        let symbolName: String
        /// HK unit used when calling `quantity.doubleValue(for:)`. The value
        /// returned is then multiplied by `displayMultiplier` for display.
        let displayUnit: HKUnit
        /// Trailing unit label shown next to the number in the UI.
        let unitLabel: String
        let aggregation: MetricAggregation
        /// Number of decimal places to show. `0` = integer.
        let formatDecimals: Int
        /// Multiplier applied AFTER the HK unit conversion. Used for percent
        /// metrics where HKUnit.percent() returns a 0…1 ratio but we want
        /// to display "98%" — set this to 100.
        let displayMultiplier: Double

        var id: String { identifier.rawValue }
    }

    /// Single source of truth for the v2.2 single-value metric list. Adding
    /// a new metric is a one-line entry here — the today reader, range
    /// reader, and UI all dispatch through this list.
    ///
    /// Aggregation rationale per metric (verify each carefully — the classic
    /// HK aggregation bug is summing rates):
    ///   • Steps: SUM. Cumulative counter; daily total is the user-facing
    ///     number.
    ///   • Heart rate, HRV, SpO2, respiratory rate, walking DSP, temperature:
    ///     AVERAGE. These are rates / instantaneous measurements; summing
    ///     them produces meaningless numbers.
    ///   • Resting heart rate: AVERAGE. RHR is typically one value per day
    ///     but averaging is robust to multiple readings.
    ///   • VO2 max: LATEST. Updates infrequently after qualifying workouts;
    ///     the most recent sample is the right "today's value."
    ///   • Wrist temperature: LATEST. Apple Watch records this overnight,
    ///     so "today's value" really means "from last night's recording."
    static var healthMetrics: [HealthMetric] {
        // Built as a computed property to avoid HKUnit static init order
        // surprises. The closure runs once and is cheap.
        [
            HealthMetric(
                identifier: .heartRate,
                displayName: "Heart rate",
                symbolName: "heart.fill",
                displayUnit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                unitLabel: "bpm",
                aggregation: .average,
                formatDecimals: 0,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                identifier: .restingHeartRate,
                displayName: "Resting HR",
                symbolName: "heart",
                displayUnit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                unitLabel: "bpm",
                aggregation: .average,
                formatDecimals: 0,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                identifier: .heartRateVariabilitySDNN,
                displayName: "HRV",
                symbolName: "waveform.path.ecg",
                displayUnit: HKUnit.secondUnit(with: .milli),
                unitLabel: "ms",
                aggregation: .average,
                formatDecimals: 0,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                identifier: .oxygenSaturation,
                displayName: "Blood oxygen",
                symbolName: "drop.fill",
                // HKUnit.percent() returns 0…1 — multiply by 100 for "98%".
                displayUnit: HKUnit.percent(),
                unitLabel: "%",
                aggregation: .average,
                formatDecimals: 0,
                displayMultiplier: 100.0
            ),
            HealthMetric(
                identifier: .respiratoryRate,
                displayName: "Respiratory rate",
                symbolName: "lungs.fill",
                displayUnit: HKUnit.count().unitDivided(by: HKUnit.minute()),
                unitLabel: "/min",
                aggregation: .average,
                formatDecimals: 0,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                identifier: .stepCount,
                displayName: "Steps",
                symbolName: "figure.walk",
                displayUnit: HKUnit.count(),
                unitLabel: "",
                aggregation: .sum,
                formatDecimals: 0,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                identifier: .vo2Max,
                displayName: "VO2 max",
                symbolName: "lungs",
                // mL/(kg·min) — composed unit
                displayUnit: HKUnit(from: "ml/kg*min"),
                unitLabel: "mL/kg·min",
                aggregation: .latest,
                formatDecimals: 1,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                // Apple Watch's overnight wrist-temp source — the spec's
                // recommended pick. If the user lacks a Watch capable of
                // wrist temp (Series 8+/Ultra), this will simply be "–".
                identifier: .appleSleepingWristTemperature,
                displayName: "Wrist temp",
                symbolName: "thermometer",
                displayUnit: HKUnit.degreeFahrenheit(),
                unitLabel: "°F",
                aggregation: .latest,
                formatDecimals: 1,
                displayMultiplier: 1.0
            ),
            HealthMetric(
                identifier: .walkingDoubleSupportPercentage,
                displayName: "Walking DSP",
                symbolName: "figure.walk.motion",
                displayUnit: HKUnit.percent(),
                unitLabel: "%",
                aggregation: .average,
                formatDecimals: 1,
                displayMultiplier: 100.0
            ),
        ]
    }

    // MARK: - Authorization

    /// The full read set for v2.2: every single-value metric type + sleep +
    /// both BP quantity types. Reuses the existing
    /// NSHealthShareUsageDescription privacy string from v1.8.2 — no new
    /// Info.plist entry needed.
    static var healthMetricsReadTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = []
        for desc in healthMetrics {
            set.insert(HKQuantityType(desc.identifier))
        }
        set.insert(HKCategoryType(.sleepAnalysis))
        set.insert(HKQuantityType(.bloodPressureSystolic))
        set.insert(HKQuantityType(.bloodPressureDiastolic))
        return set
    }

    /// One-shot prompt asking for read access to every metric the view
    /// surfaces. Same return semantics as the v1.9 energy auth — false only
    /// on a real error; user denial isn't detectable for reads.
    static func requestHealthMetricsReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: healthMetricsReadTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Generic readers (single-value metrics)

    /// Today's value for a metric, dispatched on aggregation. Window is
    /// today's start-of-day → now for average/sum. For latest, looks back
    /// 30 days to catch sparse metrics like VO2 max and wrist temp.
    static func readMetricToday(_ desc: HealthMetric) async -> Double? {
        guard isAvailable else { return nil }
        let cal = Calendar.current
        let now = Date.now
        let startOfDay = cal.startOfDay(for: now)
        switch desc.aggregation {
        case .average:
            return await statistic(desc, from: startOfDay, to: now, option: .discreteAverage, extract: { $0.averageQuantity() })
        case .sum:
            return await statistic(desc, from: startOfDay, to: now, option: .cumulativeSum, extract: { $0.sumQuantity() })
        case .latest:
            // 30-day lookback — surfaces VO2 max + wrist temp from recent
            // overnight readings even when today produced no fresh sample.
            let lookback = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return await latestSampleValue(desc, from: lookback, to: now)
        }
    }

    /// Per-day series for a metric, keyed by start-of-day. Days with no
    /// data are absent from the dict — never present with value 0.
    static func readMetricByDay(_ desc: HealthMetric, from start: Date, to end: Date) async -> [Date: Double] {
        guard isAvailable else { return [:] }
        switch desc.aggregation {
        case .average:
            return await statisticsCollection(desc, from: start, to: end, option: .discreteAverage, extract: { $0.averageQuantity() })
        case .sum:
            return await statisticsCollection(desc, from: start, to: end, option: .cumulativeSum, extract: { $0.sumQuantity() })
        case .latest:
            // For sparse "latest" metrics, fetch raw samples and keep the
            // most-recent-per-day. No interpolation between samples.
            return await latestSampleByDay(desc, from: start, to: end)
        }
    }

    // MARK: - Dispatch helpers

    private static func statistic(
        _ desc: HealthMetric,
        from start: Date,
        to end: Date,
        option: HKStatisticsOptions,
        extract: @escaping (HKStatistics) -> HKQuantity?
    ) async -> Double? {
        let type = HKQuantityType(desc.identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: option
        )
        do {
            let stats = try await descriptor.result(for: store)
            guard let stats, let q = extract(stats) else { return nil }
            return q.doubleValue(for: desc.displayUnit) * desc.displayMultiplier
        } catch {
            return nil
        }
    }

    private static func statisticsCollection(
        _ desc: HealthMetric,
        from rangeStart: Date,
        to rangeEnd: Date,
        option: HKStatisticsOptions,
        extract: @escaping (HKStatistics) -> HKQuantity?
    ) async -> [Date: Double] {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: rangeStart)
        let type = HKQuantityType(desc.identifier)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: rangeEnd, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: option,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var result: [Date: Double] = [:]
            collection.enumerateStatistics(from: anchor, to: rangeEnd) { stat, _ in
                if let q = extract(stat) {
                    let day = cal.startOfDay(for: stat.startDate)
                    result[day] = q.doubleValue(for: desc.displayUnit) * desc.displayMultiplier
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    private static func latestSampleValue(
        _ desc: HealthMetric,
        from start: Date,
        to end: Date
    ) async -> Double? {
        let type = HKQuantityType(desc.identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        do {
            let samples = try await descriptor.result(for: store)
            guard let s = samples.first else { return nil }
            return s.quantity.doubleValue(for: desc.displayUnit) * desc.displayMultiplier
        } catch {
            return nil
        }
    }

    private static func latestSampleByDay(
        _ desc: HealthMetric,
        from rangeStart: Date,
        to rangeEnd: Date
    ) async -> [Date: Double] {
        let cal = Calendar.current
        let type = HKQuantityType(desc.identifier)
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            // Latest-per-day: walking samples in chronological order, last
            // value wins for each day. Days with no samples are absent (nil
            // ≠ 0 — never default to 0).
            var byDay: [Date: Double] = [:]
            for sample in samples {
                let day = cal.startOfDay(for: sample.startDate)
                byDay[day] = sample.quantity.doubleValue(for: desc.displayUnit) * desc.displayMultiplier
            }
            return byDay
        } catch {
            return [:]
        }
    }

    // MARK: - Sleep (category type, not quantity — bespoke reader)

    struct SleepNight {
        let start: Date
        let end: Date
        /// REM + Core + Deep + asleepUnspecified — total time the user was
        /// actually asleep (NOT counting Awake / inBed). Always non-nil if
        /// the SleepNight exists, but may be zero if the session was all
        /// awake / inBed.
        let asleepDuration: TimeInterval
        let remDuration: TimeInterval
        let coreDuration: TimeInterval
        let deepDuration: TimeInterval
        let awakeDuration: TimeInterval
    }

    /// Last night's sleep, derived from the most recent set of contiguous
    /// HKCategoryType(.sleepAnalysis) samples in the past 36 hours.
    /// "Contiguous" = samples ending within 12 hours of the latest end date.
    /// Robust enough for a single sleep session per night.
    static func readLastNightSleep() async -> SleepNight? {
        guard isAvailable else { return nil }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .hour, value: -36, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: .now, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            guard !samples.isEmpty else { return nil }
            return mostRecentSession(from: samples, cal: cal)
        } catch {
            return nil
        }
    }

    /// Nightly asleep-duration series for the range, keyed by the morning
    /// the user woke up (the calendar day of each session's last endDate).
    /// Sessions are determined by the same 12-hour adjacency rule used by
    /// `readLastNightSleep`. Nights with no recorded sleep are absent —
    /// never present with value 0.
    static func readSleepDurationByNight(from start: Date, to end: Date) async -> [Date: TimeInterval] {
        guard isAvailable else { return [:] }
        let cal = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        do {
            let samples = try await descriptor.result(for: store)
            // Group asleep samples by morning-of-wake (the day containing
            // each sample's endDate). Sum asleep durations.
            var byMorning: [Date: TimeInterval] = [:]
            for sample in samples {
                guard isAsleep(sample) else { continue }
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                let morning = cal.startOfDay(for: sample.endDate)
                byMorning[morning, default: 0] += duration
            }
            return byMorning
        } catch {
            return [:]
        }
    }

    private static func mostRecentSession(from samples: [HKCategorySample], cal: Calendar) -> SleepNight? {
        guard let latestEnd = samples.map(\.endDate).max() else { return nil }
        guard let sessionStart = cal.date(byAdding: .hour, value: -12, to: latestEnd) else { return nil }
        let sessionSamples = samples.filter { $0.endDate >= sessionStart }
        guard !sessionSamples.isEmpty else { return nil }

        var rem: TimeInterval = 0
        var core: TimeInterval = 0
        var deep: TimeInterval = 0
        var unspecified: TimeInterval = 0
        var awake: TimeInterval = 0
        for s in sessionSamples {
            let d = s.endDate.timeIntervalSince(s.startDate)
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            switch value {
            case .asleepREM:           rem += d
            case .asleepCore:          core += d
            case .asleepDeep:          deep += d
            case .asleepUnspecified:   unspecified += d
            case .awake:               awake += d
            case .asleep:              unspecified += d   // legacy iOS <16
            case .inBed:               break              // not counted as asleep
            @unknown default:          break
            }
        }
        return SleepNight(
            start: sessionSamples.first?.startDate ?? latestEnd,
            end: latestEnd,
            asleepDuration: rem + core + deep + unspecified,
            remDuration: rem,
            coreDuration: core,
            deepDuration: deep,
            awakeDuration: awake
        )
    }

    private static func isAsleep(_ s: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return false }
        switch value {
        case .asleepREM, .asleepCore, .asleepDeep, .asleepUnspecified, .asleep:
            return true
        default:
            return false
        }
    }

    // MARK: - Blood pressure (paired quantities — bespoke reader)

    struct BPReading: Identifiable {
        let id = UUID()
        let date: Date
        let systolicMMHG: Double
        let diastolicMMHG: Double
    }

    /// Latest BP reading within the past 30 days. Pairs the most recent
    /// systolic sample with the most recent diastolic sample by exact
    /// startDate match. Since BP is recorded as a pair in the Health app,
    /// the timestamps line up.
    static func readBloodPressureLatest() async -> BPReading? {
        guard isAvailable else { return nil }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: cutoff, end: .now, options: .strictStartDate)

        async let sys = quantitySamples(type: HKQuantityType(.bloodPressureSystolic),
                                        predicate: predicate, limit: 1, reverse: true)
        async let dia = quantitySamples(type: HKQuantityType(.bloodPressureDiastolic),
                                        predicate: predicate, limit: 1, reverse: true)
        let (sysSamples, diaSamples) = await (sys, dia)
        guard let s = sysSamples.first, let d = diaSamples.first else { return nil }
        return BPReading(
            date: s.startDate,
            systolicMMHG: s.quantity.doubleValue(for: HKUnit.millimeterOfMercury()),
            diastolicMMHG: d.quantity.doubleValue(for: HKUnit.millimeterOfMercury())
        )
    }

    /// BP readings in the given range, paired by exact startDate match.
    /// Unpaired samples (very rare in practice) are dropped.
    static func readBloodPressureSeries(from start: Date, to end: Date) async -> [BPReading] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let sys = quantitySamples(type: HKQuantityType(.bloodPressureSystolic),
                                        predicate: predicate, limit: 0, reverse: false)
        async let dia = quantitySamples(type: HKQuantityType(.bloodPressureDiastolic),
                                        predicate: predicate, limit: 0, reverse: false)
        let (sysSamples, diaSamples) = await (sys, dia)

        var diaByDate: [Date: HKQuantitySample] = [:]
        for d in diaSamples { diaByDate[d.startDate] = d }

        return sysSamples.compactMap { s in
            guard let d = diaByDate[s.startDate] else { return nil }
            return BPReading(
                date: s.startDate,
                systolicMMHG: s.quantity.doubleValue(for: HKUnit.millimeterOfMercury()),
                diastolicMMHG: d.quantity.doubleValue(for: HKUnit.millimeterOfMercury())
            )
        }
    }

    private static func quantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate,
        limit: Int,
        reverse: Bool
    ) async -> [HKQuantitySample] {
        let sort: [SortDescriptor<HKQuantitySample>] = [
            SortDescriptor(\.startDate, order: reverse ? .reverse : .forward)
        ]
        do {
            if limit > 0 {
                let descriptor = HKSampleQueryDescriptor(
                    predicates: [.quantitySample(type: type, predicate: predicate)],
                    sortDescriptors: sort,
                    limit: limit
                )
                return try await descriptor.result(for: store)
            } else {
                let descriptor = HKSampleQueryDescriptor(
                    predicates: [.quantitySample(type: type, predicate: predicate)],
                    sortDescriptors: sort
                )
                return try await descriptor.result(for: store)
            }
        } catch {
            return []
        }
    }
}
