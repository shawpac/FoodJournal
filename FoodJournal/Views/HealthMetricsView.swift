import SwiftUI
import Charts
import HealthKit

/// v2.2 — Read-only Apple Health dashboard. Pushed from the Workouts tab.
///
/// Layout:
///   • **Today** tiles, one per metric, plus special tiles for sleep (last
///     night duration + stage breakdown) and BP (latest pair or "–"). All
///     tiles tappable to push a per-metric trend chart.
///   • Trend pages use Swift Charts (iOS 16+; project targets iOS 18+).
///     Missing days are SKIPPED — never plotted as 0 or interpolated.
///
/// Same invariants as v1.9 / v2.0: data is read on demand, never cached
/// locally; nil ≠ 0; HK read-denial isn't detectable so a permanently "–"
/// tile may be denied permission OR genuinely no data — the UI cannot tell
/// the user which.
struct HealthMetricsView: View {
    @State private var hasRequestedAuth = false

    // Today values — one per metric, plus sleep and BP.
    @State private var todayValues: [String: Double] = [:]   // descriptor.id → value
    @State private var lastNightSleep: HealthService.SleepNight?
    @State private var latestBP: HealthService.BPReading?
    @State private var isLoading = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Today")
                    LazyVGrid(columns: columns, spacing: 12) {
                        sleepTile
                        bpTile
                        ForEach(HealthService.healthMetrics) { metric in
                            NavigationLink {
                                MetricTrendView(metric: metric)
                            } label: {
                                metricTile(metric)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // v2.3a — Lab results entry. Pushes the labs surface
                    // (panels, manual entry, photo import, marker trends).
                    sectionHeader("Lab results")
                    NavigationLink {
                        LabsView()
                    } label: {
                        labsEntryRow
                    }
                    .buttonStyle(.plain)

                    disclaimerFooter
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Health")
            .task {
                if !hasRequestedAuth {
                    hasRequestedAuth = true
                    _ = await HealthService.requestHealthMetricsReadAuthorization()
                }
                await reloadAll()
            }
            .refreshable {
                await reloadAll()
            }
        }
    }

    // MARK: - Loading

    private func reloadAll() async {
        isLoading = true
        // Fan out — let all HK calls overlap. The actor is MainActor but
        // each call suspends inside HealthKit, so the main thread stays
        // responsive.
        async let metrics = loadAllMetrics()
        async let sleep = HealthService.readLastNightSleep()
        async let bp = HealthService.readBloodPressureLatest()
        let (values, sleepRes, bpRes) = await (metrics, sleep, bp)
        todayValues = values
        lastNightSleep = sleepRes
        latestBP = bpRes
        isLoading = false
    }

    private func loadAllMetrics() async -> [String: Double] {
        var out: [String: Double] = [:]
        for metric in HealthService.healthMetrics {
            if let v = await HealthService.readMetricToday(metric) {
                out[metric.id] = v
            }
        }
        return out
    }

    // MARK: - Sleep tile

    private var sleepTile: some View {
        NavigationLink {
            SleepTrendView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(.purple)
                    Text("Last night")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let s = lastNightSleep, s.asleepDuration > 0 {
                    Text(formatDuration(s.asleepDuration))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    sleepStagesRow(s)
                } else {
                    Text("–")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text("no data")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func sleepStagesRow(_ s: HealthService.SleepNight) -> some View {
        HStack(spacing: 8) {
            stagePill(label: "REM", color: .blue, duration: s.remDuration)
            stagePill(label: "Core", color: .teal, duration: s.coreDuration)
            stagePill(label: "Deep", color: .indigo, duration: s.deepDuration)
        }
    }

    private func stagePill(label: String, color: Color, duration: TimeInterval) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(duration > 0 ? formatShortDuration(duration) : "–")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Blood pressure tile

    private var bpTile: some View {
        NavigationLink {
            BPTrendView()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.red)
                    Text("Blood pressure")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let bp = latestBP {
                    Text("\(Int(bp.systolicMMHG.rounded()))/\(Int(bp.diastolicMMHG.rounded()))")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(bp.date, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("–")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text("requires manual entry or a cuff")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generic metric tile

    private func metricTile(_ metric: HealthService.HealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbolName)
                    .foregroundStyle(.orange)
                Text(metric.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let v = todayValues[metric.id] {
                    Text(formatMetricValue(v, decimals: metric.formatDecimals))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    if !metric.unitLabel.isEmpty {
                        Text(metric.unitLabel)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("–")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text("no data")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }

    /// v2.3a entry row pushing LabsView. Single tappable card matching the
    /// rest of the dashboard style.
    private var labsEntryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lab results")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("Manual entry + photo import. Display only — no medical interpretation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var disclaimerFooter: some View {
        Text("Apple Health is the source of truth. A permanently \"–\" tile may mean either no data exists OR you denied read permission for that type — Apple's privacy design hides which. Check the Health app's permission screen if unsure.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

// MARK: - Generic single-metric trend page

private struct MetricTrendView: View {
    let metric: HealthService.HealthMetric

    @State private var preset: RangePreset = .sevenDays
    @State private var byDay: [Date: Double] = [:]
    @State private var isLoading = false

    enum RangePreset: String, CaseIterable, Identifiable {
        case sevenDays = "7 days"
        case thirtyDays = "30 days"
        var id: String { rawValue }
    }

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
        let daysBack = preset == .sevenDays ? 6 : 29
        let start = cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: .now)) ?? .now
        return (start, endOfToday)
    }

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $preset) {
                    ForEach(RangePreset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if byDay.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: metric.symbolName)
                            .foregroundStyle(.tertiary)
                        Text("No data in this range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    chart
                    summaryRows
                }
            } header: {
                Text(metric.displayName)
            } footer: {
                Text("Missing days are gaps in the chart, not zeros. \(metric.aggregation == .sum ? "Daily totals." : metric.aggregation == .latest ? "Most recent sample per day." : "Daily averages.")")
            }
        }
        .navigationTitle(metric.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: preset) {
            await reload()
        }
    }

    private var sortedPoints: [(Date, Double)] {
        byDay.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
    }

    @ViewBuilder
    private var chart: some View {
        if sortedPoints.count == 1 {
            // One-point case — show the value with no implied trend line.
            HStack {
                Text(sortedPoints[0].0, format: Date.FormatStyle(date: .abbreviated))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(formatMetricValue(sortedPoints[0].1, decimals: metric.formatDecimals)) \(metric.unitLabel)")
                    .font(.body.monospacedDigit())
            }
            .padding(.vertical, 8)
            Text("Only one day of data in this range.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Chart {
                ForEach(sortedPoints, id: \.0) { pt in
                    LineMark(
                        x: .value("Date", pt.0),
                        y: .value(metric.displayName, pt.1)
                    )
                    .foregroundStyle(.orange)
                    PointMark(
                        x: .value("Date", pt.0),
                        y: .value(metric.displayName, pt.1)
                    )
                    .foregroundStyle(.orange)
                }
            }
            .frame(height: 160)
            // Skip missing days: only days present in `byDay` produce
            // points. The Chart renders straight segments between adjacent
            // points; gaps in the date axis remain visible by virtue of the
            // X axis being linear over time.
        }
    }

    private var summaryRows: some View {
        let values = byDay.values
        let n = values.count
        let avg = values.reduce(0, +) / Double(max(n, 1))
        let mn = values.min()
        let mx = values.max()
        return Group {
            summaryRow("Average", value: avg)
            if let mn { summaryRow("Min", value: mn) }
            if let mx { summaryRow("Max", value: mx) }
            HStack {
                Text("Days with data")
                Spacer()
                Text("\(n)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(formatMetricValue(value, decimals: metric.formatDecimals)) \(metric.unitLabel)")
                .font(.body.monospacedDigit())
        }
    }

    private func reload() async {
        isLoading = true
        byDay = await HealthService.readMetricByDay(metric, from: dateRange.start, to: dateRange.end)
        isLoading = false
    }
}

// MARK: - Sleep trend (nightly duration over range)

private struct SleepTrendView: View {
    @State private var preset: MetricTrendView.RangePreset = .sevenDays
    @State private var byNight: [Date: TimeInterval] = [:]

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
        let daysBack = preset == .sevenDays ? 6 : 29
        let start = cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: .now)) ?? .now
        return (start, endOfToday)
    }

    private var sortedPoints: [(Date, Double)] {
        // Convert seconds → hours for display.
        byNight.map { ($0.key, $0.value / 3600.0) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $preset) {
                    ForEach(MetricTrendView.RangePreset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if sortedPoints.isEmpty {
                    HStack {
                        Image(systemName: "bed.double")
                            .foregroundStyle(.tertiary)
                        Text("No sleep data in this range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if sortedPoints.count == 1 {
                    HStack {
                        Text(sortedPoints[0].0, format: Date.FormatStyle(date: .abbreviated))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatHourFraction(sortedPoints[0].1))
                            .font(.body.monospacedDigit())
                    }
                    Text("Only one night of data in this range.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Chart {
                        ForEach(sortedPoints, id: \.0) { pt in
                            LineMark(
                                x: .value("Date", pt.0),
                                y: .value("Hours", pt.1)
                            )
                            .foregroundStyle(.purple)
                            PointMark(
                                x: .value("Date", pt.0),
                                y: .value("Hours", pt.1)
                            )
                            .foregroundStyle(.purple)
                        }
                    }
                    .frame(height: 160)
                    let avg = sortedPoints.map(\.1).reduce(0, +) / Double(sortedPoints.count)
                    HStack {
                        Text("Average").font(.body)
                        Spacer()
                        Text(formatHourFraction(avg))
                            .font(.body.monospacedDigit())
                    }
                    HStack {
                        Text("Nights with data").font(.body)
                        Spacer()
                        Text("\(sortedPoints.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Asleep duration per night")
            } footer: {
                Text("Nights with no recorded sleep are gaps, not zero. Keyed by the morning of waking up.")
            }
        }
        .navigationTitle("Sleep trend")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: preset) {
            byNight = await HealthService.readSleepDurationByNight(from: dateRange.start, to: dateRange.end)
        }
    }
}

// MARK: - BP trend (systolic + diastolic series)

private struct BPTrendView: View {
    @State private var preset: MetricTrendView.RangePreset = .thirtyDays
    @State private var readings: [HealthService.BPReading] = []

    private var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: .now) ?? .now
        let daysBack = preset == .sevenDays ? 6 : 29
        let start = cal.date(byAdding: .day, value: -daysBack, to: cal.startOfDay(for: .now)) ?? .now
        return (start, endOfToday)
    }

    var body: some View {
        Form {
            Section {
                Picker("Range", selection: $preset) {
                    ForEach(MetricTrendView.RangePreset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if readings.isEmpty {
                    HStack {
                        Image(systemName: "heart.text.square")
                            .foregroundStyle(.tertiary)
                        Text("No blood pressure readings in this range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if readings.count == 1 {
                    Text("Only one reading in this range.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    HStack {
                        Text(readings[0].date, format: Date.FormatStyle(date: .abbreviated))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(readings[0].systolicMMHG.rounded()))/\(Int(readings[0].diastolicMMHG.rounded())) mmHg")
                            .font(.body.monospacedDigit())
                    }
                } else {
                    Chart {
                        ForEach(readings) { r in
                            LineMark(
                                x: .value("Date", r.date),
                                y: .value("Systolic", r.systolicMMHG)
                            )
                            .foregroundStyle(by: .value("Series", "Systolic"))
                            PointMark(
                                x: .value("Date", r.date),
                                y: .value("Systolic", r.systolicMMHG)
                            )
                            .foregroundStyle(by: .value("Series", "Systolic"))

                            LineMark(
                                x: .value("Date", r.date),
                                y: .value("Diastolic", r.diastolicMMHG)
                            )
                            .foregroundStyle(by: .value("Series", "Diastolic"))
                            PointMark(
                                x: .value("Date", r.date),
                                y: .value("Diastolic", r.diastolicMMHG)
                            )
                            .foregroundStyle(by: .value("Series", "Diastolic"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "Systolic": .red,
                        "Diastolic": .blue
                    ])
                    .frame(height: 180)

                    let sysAvg = readings.map(\.systolicMMHG).reduce(0, +) / Double(readings.count)
                    let diaAvg = readings.map(\.diastolicMMHG).reduce(0, +) / Double(readings.count)
                    HStack {
                        Text("Average").font(.body)
                        Spacer()
                        Text("\(Int(sysAvg.rounded()))/\(Int(diaAvg.rounded())) mmHg")
                            .font(.body.monospacedDigit())
                    }
                    HStack {
                        Text("Readings").font(.body)
                        Spacer()
                        Text("\(readings.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Systolic / Diastolic")
            } footer: {
                Text("Apple Watch does not measure blood pressure. Manual entry in the Health app or a connected cuff is required.")
            }
        }
        .navigationTitle("Blood pressure")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: preset) {
            readings = await HealthService.readBloodPressureSeries(from: dateRange.start, to: dateRange.end)
        }
    }
}

// MARK: - Formatters (file-private)

private func formatMetricValue(_ v: Double, decimals: Int) -> String {
    if decimals <= 0 {
        return "\(Int(v.rounded()))"
    }
    return String(format: "%.\(decimals)f", v)
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int((seconds / 60).rounded())
    let h = totalMinutes / 60
    let m = totalMinutes % 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private func formatShortDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int((seconds / 60).rounded())
    let h = totalMinutes / 60
    let m = totalMinutes % 60
    if h > 0 { return m > 0 ? "\(h)h\(m)" : "\(h)h" }
    return "\(m)m"
}

private func formatHourFraction(_ hours: Double) -> String {
    let h = Int(hours)
    let m = Int(((hours - Double(h)) * 60).rounded())
    if m == 0 { return "\(h)h" }
    return "\(h)h \(m)m"
}
