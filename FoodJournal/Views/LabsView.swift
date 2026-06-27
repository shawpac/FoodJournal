import SwiftUI
import SwiftData
import Charts

// MARK: - LabsView (root labs surface)
/// v2.3a — Lab results dashboard, pushed from the Health Data tab.
///
/// SAFETY: this surface and every descendant DISPLAYS values and FLAGS them
/// against the LAB'S OWN PRINTED REFERENCE RANGE. It does NOT INTERPRET the
/// results — no commentary on what abnormal values might mean, no advice, no
/// medical opinion. A result with no printed range shows NO flag, never a
/// guessed one. Apple Health clinical records (FHIR) are out of scope here —
/// that's v2.3b.
struct LabsView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<LabPanel> { $0.pendingDeleteAt == nil },
        sort: \LabPanel.collectedDate,
        order: .reverse
    ) private var panels: [LabPanel]

    @State private var showingManualEntry = false
    @State private var showingPhotoImport = false
    @State private var pendingUndo: PendingPanelDeletion?

    private struct PendingPanelDeletion: Identifiable {
        let id = UUID()
        let panel: LabPanel
        let workItem: DispatchWorkItem
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LabMarkerPickerView()
                } label: {
                    Label("Marker trends", systemImage: "chart.line.uptrend.xyaxis")
                }
            }

            Section {
                Button {
                    showingManualEntry = true
                } label: {
                    Label("Add panel manually", systemImage: "square.and.pencil")
                }
                Button {
                    showingPhotoImport = true
                } label: {
                    Label("Import from photo or PDF", systemImage: "doc.text.viewfinder")
                }
            } footer: {
                Text("Photo or PDF import transcribes a printed lab report, a screenshot, or the direct PDF you can export from Apple Health → Browse → Lab Results → Share → PDF into an editable review screen. Nothing saves until you confirm.")
            }

            if panels.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No panels yet")
                            .font(.body.weight(.medium))
                        Text("Add one manually or import a photo of a lab report.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section("Panels") {
                    ForEach(panels) { panel in
                        NavigationLink {
                            LabPanelDetailView(panel: panel)
                        } label: {
                            panelRow(panel)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                scheduleDelete(panel)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Text("This surface flags results against the lab's own printed reference range. It does not interpret your results. Talk to a clinician about anything medical.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("Lab results")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingManualEntry) {
            LabPanelManualSheet()
        }
        .sheet(isPresented: $showingPhotoImport) {
            LabPhotoImportSheet()
        }
        .overlay(alignment: .bottom) {
            if let pending = pendingUndo {
                undoToast(pending)
            }
        }
    }

    private func panelRow(_ panel: LabPanel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(panel.collectedDate, format: Date.FormatStyle(date: .abbreviated))
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(panel.results.count) result\(panel.results.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(panel.source)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Soft delete with 5s undo (cascade fires on commit)

    private func scheduleDelete(_ panel: LabPanel) {
        panel.pendingDeleteAt = .now
        let workItem = DispatchWorkItem { commitDelete(panel) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        pendingUndo = PendingPanelDeletion(panel: panel, workItem: workItem)
        Haptic.light()
    }

    private func undo(_ pending: PendingPanelDeletion) {
        pending.workItem.cancel()
        pending.panel.pendingDeleteAt = nil
        pendingUndo = nil
    }

    private func commitDelete(_ panel: LabPanel) {
        guard panel.pendingDeleteAt != nil else { return }
        context.delete(panel)
        pendingUndo = nil
    }

    private func undoToast(_ pending: PendingPanelDeletion) -> some View {
        HStack(spacing: 12) {
            Text("Panel deleted")
                .font(.callout)
            Spacer()
            Button("Undo") { undo(pending) }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }
}

// MARK: - LabPanelDetailView (read-only listing)
struct LabPanelDetailView: View {
    @Bindable var panel: LabPanel

    private var sortedResults: [LabResult] {
        panel.results.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Collected", value: panel.collectedDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Source", value: panel.source)
                LabeledContent("Imported", value: panel.importedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if sortedResults.isEmpty {
                Section {
                    Text("No results recorded for this panel.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Results") {
                    ForEach(sortedResults) { r in
                        LabResultRow(result: r)
                    }
                }
            }

            Section {
                Text("In/out-of-range flags come from this lab's own printed range. No range printed → no flag.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .navigationTitle(panel.source)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - LabResultRow (shared row renderer)
/// Renders one LabResult with a NEUTRAL in/out-of-range dot derived from the
/// source range. "out of range" is the only out-of-range language used — no
/// "high", "low", "elevated", "concerning", or anything that could read as
/// medical commentary.
struct LabResultRow: View {
    let result: LabResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.testName)
                    .font(.body.weight(.medium))
                Spacer()
                rangeIndicator
            }
            HStack(spacing: 6) {
                Text(displayValue)
                    .font(.body.monospacedDigit())
                if let unit = result.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let rangeStr = displayRange {
                    Text("Range: \(rangeStr)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var displayValue: String {
        if let v = result.value { return formatLabValue(v) }
        if let t = result.valueText, !t.isEmpty { return t }
        return "–"
    }

    private var displayRange: String? {
        if let low = result.refRangeLow, let high = result.refRangeHigh {
            return "\(formatLabValue(low))–\(formatLabValue(high))"
        }
        if let low = result.refRangeLow {
            return "≥ \(formatLabValue(low))"
        }
        if let high = result.refRangeHigh {
            return "≤ \(formatLabValue(high))"
        }
        if let t = result.refRangeText, !t.isEmpty { return t }
        return nil
    }

    @ViewBuilder
    private var rangeIndicator: some View {
        switch rangeStatus {
        case .inRange:
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .accessibilityLabel("in range")
        case .outOfRange:
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                Text("out of range")
                    .font(.caption2)
            }
            .foregroundStyle(.orange)
        case .unknown:
            EmptyView()
        }
    }

    enum RangeStatus { case inRange, outOfRange, unknown }

    /// Flag ONLY from the source's printed numeric range. `refRangeText`
    /// alone (e.g. "<5.7", "Negative") doesn't drive a flag — interpreting
    /// inequality text is interpretation, which is out of scope. Missing
    /// `value` → unknown (no flag).
    private var rangeStatus: RangeStatus {
        guard let value = result.value else { return .unknown }
        let low = result.refRangeLow
        let high = result.refRangeHigh
        if low != nil || high != nil {
            if let low = low, value < low { return .outOfRange }
            if let high = high, value > high { return .outOfRange }
            return .inRange
        }
        return .unknown
    }
}

// MARK: - LabPanelManualSheet (Path A: manual entry)
struct LabPanelManualSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var collectedDate: Date = .now
    @State private var source: String = ""
    @State private var rows: [ResultDraft] = [.init()]

    struct ResultDraft: Identifiable {
        let id = UUID()
        var testName: String = ""
        var valueStr: String = ""
        var valueText: String = ""
        var unit: String = ""
        var refLowStr: String = ""
        var refHighStr: String = ""
        var refRangeText: String = ""
    }

    private var canSave: Bool {
        !source.trimmingCharacters(in: .whitespaces).isEmpty &&
        rows.contains(where: { !$0.testName.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    DatePicker("Collected", selection: $collectedDate, in: ...Date.now, displayedComponents: .date)
                    TextField("Source (LabCorp, PCP, …)", text: $source)
                }

                ForEach($rows) { $row in
                    Section {
                        TextField("Test name", text: $row.testName)
                        HStack {
                            TextField("Value", text: $row.valueStr)
                                .keyboardType(.decimalPad)
                            TextField("or text", text: $row.valueText)
                        }
                        TextField("Unit (mg/dL, %, …)", text: $row.unit)
                        HStack {
                            TextField("Range low", text: $row.refLowStr)
                                .keyboardType(.decimalPad)
                            TextField("high", text: $row.refHighStr)
                                .keyboardType(.decimalPad)
                        }
                        TextField("Range text (e.g. <5.7)", text: $row.refRangeText)
                    } header: {
                        HStack {
                            Text("Result")
                            Spacer()
                            if rows.count > 1 {
                                Button(role: .destructive) {
                                    if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                                        rows.remove(at: idx)
                                    }
                                } label: {
                                    Text("Remove").font(.caption)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        rows.append(.init())
                    } label: {
                        Label("Add another result", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    Text("Enter values and ranges EXACTLY as your lab printed them. Leave any field blank if it's not on the report — the app shows no flag for results without a printed numeric range.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Add panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return }
        let panel = LabPanel(collectedDate: collectedDate, source: trimmedSource)
        context.insert(panel)
        var order = 0
        for row in rows {
            let trimmedName = row.testName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let result = LabResult(
                testName: trimmedName,
                normalizedName: LabMarker.normalize(trimmedName),
                value: emptyToDouble(row.valueStr),
                valueText: emptyToNil(row.valueText),
                unit: emptyToNil(row.unit),
                refRangeLow: emptyToDouble(row.refLowStr),
                refRangeHigh: emptyToDouble(row.refHighStr),
                refRangeText: emptyToNil(row.refRangeText),
                order: order
            )
            result.panel = panel
            context.insert(result)
            order += 1
        }
        Haptic.success()
        dismiss()
    }
}

// MARK: - LabMarkerPickerView (pick a marker → trend)
struct LabMarkerPickerView: View {
    @Query(
        filter: #Predicate<LabPanel> { $0.pendingDeleteAt == nil },
        sort: \LabPanel.collectedDate, order: .reverse
    ) private var panels: [LabPanel]

    @AppStorage(LabMarkerAliases.storageKey) private var aliasesJSON: String = ""
    @State private var showingMergeSheet = false

    private struct MarkerSummary: Identifiable {
        let canonical: String
        var displayName: String
        var sampleCount: Int
        var numericCount: Int
        var id: String { canonical }
    }

    private var markers: [MarkerSummary] {
        let aliases = LabMarkerAliases.decode(aliasesJSON)
        var groups: [String: MarkerSummary] = [:]
        for panel in panels {
            for r in panel.results where !r.normalizedName.isEmpty {
                let canonical = LabMarkerAliases.canonical(of: r.normalizedName, aliases: aliases)
                let isNumeric = r.value != nil
                if var existing = groups[canonical] {
                    existing.sampleCount += 1
                    if isNumeric { existing.numericCount += 1 }
                    groups[canonical] = existing
                } else {
                    groups[canonical] = MarkerSummary(
                        canonical: canonical,
                        displayName: r.testName,
                        sampleCount: 1,
                        numericCount: isNumeric ? 1 : 0
                    )
                }
            }
        }
        return groups.values.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingMergeSheet = true
                } label: {
                    Label("Merge markers", systemImage: "arrow.triangle.merge")
                }
            } footer: {
                Text("Auto-match groups results with identical normalized names (HbA1c, Hb-A1c, HB A1C all merge). For different names that mean the same test (Hemoglobin A1c ↔ HbA1c), use Merge markers. The app intentionally won't auto-merge non-exact matches — a wrong merge is hard to undo.")
            }

            if markers.isEmpty {
                Section {
                    Text("No markers yet. Add a panel with results first.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Markers") {
                    ForEach(markers) { marker in
                        NavigationLink {
                            LabMarkerTrendView(canonical: marker.canonical, displayName: marker.displayName)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(marker.displayName)
                                    .font(.body.weight(.medium))
                                let extra = marker.sampleCount - marker.numericCount
                                Text("\(marker.sampleCount) sample\(marker.sampleCount == 1 ? "" : "s")\(extra > 0 ? " (\(extra) qualitative)" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Marker trends")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMergeSheet) {
            LabMarkerMergeSheet()
        }
    }
}

// MARK: - LabMarkerTrendView (chart for one marker)
struct LabMarkerTrendView: View {
    let canonical: String
    let displayName: String

    @Query(
        filter: #Predicate<LabPanel> { $0.pendingDeleteAt == nil },
        sort: \LabPanel.collectedDate
    ) private var panels: [LabPanel]

    @AppStorage(LabMarkerAliases.storageKey) private var aliasesJSON: String = ""

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let unit: String?
        let refLow: Double?
        let refHigh: Double?
    }

    private var points: [Point] {
        let aliases = LabMarkerAliases.decode(aliasesJSON)
        var out: [Point] = []
        for panel in panels {
            for r in panel.results {
                let c = LabMarkerAliases.canonical(of: r.normalizedName, aliases: aliases)
                guard c == canonical, let v = r.value else { continue }
                out.append(Point(date: panel.collectedDate, value: v, unit: r.unit,
                                 refLow: r.refRangeLow, refHigh: r.refRangeHigh))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Returns the shared (low, high) range only when every plotted point's
    /// numeric range matches strictly. Different vendors print different
    /// ranges; rather than average or pick one (an interpretation), we show
    /// NO band when ranges vary, and surface that in the footer.
    private var consistentRange: (low: Double, high: Double)? {
        let withRange = points.compactMap { p -> (Double, Double)? in
            guard let l = p.refLow, let h = p.refHigh else { return nil }
            return (l, h)
        }
        guard !withRange.isEmpty, withRange.count == points.count else { return nil }
        guard let first = withRange.first else { return nil }
        for r in withRange where r != first { return nil }
        return first
    }

    private var qualitativeSamples: [(date: Date, text: String, unit: String?)] {
        let aliases = LabMarkerAliases.decode(aliasesJSON)
        var out: [(date: Date, text: String, unit: String?)] = []
        for panel in panels {
            for r in panel.results {
                let c = LabMarkerAliases.canonical(of: r.normalizedName, aliases: aliases)
                guard c == canonical, r.value == nil, let t = r.valueText, !t.isEmpty else { continue }
                out.append((panel.collectedDate, t, r.unit))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    var body: some View {
        Form {
            if points.isEmpty && qualitativeSamples.isEmpty {
                Section {
                    Text("No samples for this marker yet.")
                        .foregroundStyle(.secondary)
                }
            }

            if !points.isEmpty {
                Section {
                    if points.count == 1 {
                        HStack {
                            Text(points[0].date, format: Date.FormatStyle(date: .abbreviated))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatLabValue(points[0].value) + (points[0].unit.map { " \($0)" } ?? ""))
                                .font(.body.monospacedDigit())
                        }
                        Text("Only one numeric sample — need 2+ to draw a trend.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        chart
                    }
                } header: {
                    Text("Trend")
                } footer: {
                    Group {
                        if consistentRange == nil {
                            Text("Reference ranges varied or were absent across these panels — no band shown. Each panel's own range still drives that panel's flag.")
                        } else {
                            Text("Shaded band is the lab's printed reference range.")
                        }
                    }
                }
            }

            if !points.isEmpty {
                Section("Samples") {
                    ForEach(points.reversed()) { pt in
                        HStack {
                            Text(pt.date, format: Date.FormatStyle(date: .abbreviated))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatLabValue(pt.value) + (pt.unit.map { " \($0)" } ?? ""))
                                .font(.body.monospacedDigit())
                        }
                    }
                }
            }

            if !qualitativeSamples.isEmpty {
                Section {
                    ForEach(qualitativeSamples.reversed(), id: \.date) { sample in
                        HStack {
                            Text(sample.date, format: Date.FormatStyle(date: .abbreviated))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(sample.text + (sample.unit.map { " \($0)" } ?? ""))
                                .font(.body.monospacedDigit())
                        }
                    }
                } header: {
                    Text("Qualitative samples")
                } footer: {
                    Text("Qualitative results are listed, not charted.")
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var chart: some View {
        Chart {
            if let range = consistentRange,
               let first = points.first,
               let last = points.last {
                RectangleMark(
                    xStart: .value("start", first.date),
                    xEnd: .value("end", last.date),
                    yStart: .value("low", range.low),
                    yEnd: .value("high", range.high)
                )
                .foregroundStyle(Color.green.opacity(0.12))
            }
            ForEach(points) { pt in
                LineMark(
                    x: .value("Date", pt.date),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(.orange)
                PointMark(
                    x: .value("Date", pt.date),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(.orange)
            }
        }
        .frame(height: 200)
    }
}

// MARK: - LabMarkerMergeSheet (manual merge tool)
struct LabMarkerMergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<LabPanel> { $0.pendingDeleteAt == nil },
        sort: \LabPanel.collectedDate, order: .reverse
    ) private var panels: [LabPanel]

    @AppStorage(LabMarkerAliases.storageKey) private var aliasesJSON: String = ""

    @State private var selected: Set<String> = []
    @State private var chosenCanonical: String?

    private struct MarkerGroup: Identifiable {
        let canonical: String
        let names: [String]
        var id: String { canonical }
    }

    private var groups: [MarkerGroup] {
        let aliases = LabMarkerAliases.decode(aliasesJSON)
        var bag: [String: [String]] = [:]
        for panel in panels {
            for r in panel.results where !r.normalizedName.isEmpty {
                let c = LabMarkerAliases.canonical(of: r.normalizedName, aliases: aliases)
                bag[c, default: []].append(r.testName)
            }
        }
        return bag.map { (canonical, names) in
            var seen = Set<String>()
            let unique = names.filter { name in
                let key = name.lowercased()
                return seen.insert(key).inserted
            }
            return MarkerGroup(canonical: canonical, names: unique)
        }.sorted { ($0.names.first?.lowercased() ?? "") < ($1.names.first?.lowercased() ?? "") }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tap two or more markers below, then pick one to keep as the canonical name — the others alias to it. Use this when the same test was named differently on different panels (HbA1c vs Hemoglobin A1c).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Markers") {
                    ForEach(groups) { group in
                        Button {
                            toggle(group.canonical)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selected.contains(group.canonical) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(group.canonical) ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.names.first ?? group.canonical)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if group.names.count > 1 {
                                        Text("Also: " + group.names.dropFirst().joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selected.count >= 2 {
                    Section("Keep as canonical") {
                        Picker("Canonical", selection: Binding<String?>(
                            get: { chosenCanonical },
                            set: { chosenCanonical = $0 }
                        )) {
                            ForEach(selected.sorted(), id: \.self) { c in
                                Text(displayName(for: c)).tag(c as String?)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            }
            .navigationTitle("Merge markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { commit() }
                        .disabled(selected.count < 2 || chosenCanonical == nil)
                }
            }
        }
    }

    private func toggle(_ canonical: String) {
        if selected.contains(canonical) {
            selected.remove(canonical)
            if chosenCanonical == canonical { chosenCanonical = selected.first }
        } else {
            selected.insert(canonical)
            if chosenCanonical == nil { chosenCanonical = canonical }
        }
    }

    private func displayName(for canonical: String) -> String {
        groups.first { $0.canonical == canonical }?.names.first ?? canonical
    }

    private func commit() {
        guard let canonical = chosenCanonical, selected.count >= 2 else { return }
        var aliases = LabMarkerAliases.decode(aliasesJSON)
        let others = selected.subtracting([canonical])
        LabMarkerAliases.merge(canonical: canonical, others: others, into: &aliases)
        aliasesJSON = LabMarkerAliases.encode(aliases)
        Haptic.success()
        dismiss()
    }
}

// MARK: - File-private helpers

private func formatLabValue(_ v: Double) -> String {
    if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
    if abs(v) >= 100 { return String(format: "%.1f", v) }
    return String(format: "%.2f", v)
}

private func emptyToNil(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

private func emptyToDouble(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Double(t)
}
