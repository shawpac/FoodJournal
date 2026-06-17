import SwiftUI
import SwiftData
import UIKit

// MARK: - CSVExportSheet
/// Settings → "Export data" → date range → bundle of food.csv + water.csv + weight.csv into share sheet.
/// Excludes soft-deleted (pendingDeleteAt != nil) food, water, and weight entries.
/// Nil optional nutrients render as empty cells, never zero — preserves the nil ≠ 0 invariant.
struct CSVExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var startDate: Date = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return cal.date(byAdding: .day, value: -29, to: today) ?? today
    }()
    @State private var endDate: Date = Calendar.current.startOfDay(for: .now)

    @State private var shareItems: [URL]?
    @State private var isShareSheetPresented = false
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var lastSummary: String?

    // v1.9 — only include energy.csv when the read toggle is on.
    @AppStorage("showCaloriesBurnedFromHealth") private var showCaloriesBurnedFromHealth: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, newStart in
                            if newStart > endDate { endDate = newStart }
                        }
                    DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section {
                    Button {
                        generateAndShare()
                    } label: {
                        if isGenerating {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Export").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isGenerating)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Generates CSV files for food, water, and weight entries, plus an energy file when calories-burned sync is on. Opens the share sheet — email, save to Files, AirDrop to your Mac, etc.")
                }

                if let lastSummary {
                    Section {
                        Text(lastSummary)
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShareSheetPresented, onDismiss: {
                // Clean up temp files after the share sheet is dismissed
                if let urls = shareItems {
                    for url in urls { try? FileManager.default.removeItem(at: url) }
                }
                shareItems = nil
            }) {
                if let shareItems {
                    ShareSheet(items: shareItems)
                }
            }
        }
    }

    // MARK: - Generation

    private func generateAndShare() {
        dismissKeyboard()
        Haptic.light()
        isGenerating = true
        errorMessage = nil
        lastSummary = nil
        Task { await performExport() }
    }

    @MainActor
    private func performExport() async {
        // Calendar-aware: include the entire end day (up to but not including next midnight).
        let cal = Calendar.current
        let rangeStart = cal.startOfDay(for: startDate)
        guard let rangeEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)) else {
            errorMessage = "Invalid date range."
            isGenerating = false
            return
        }

        do {
            // Food entries: exclude soft-deleted, sort chronologically
            let foodDescriptor = FetchDescriptor<FoodEntry>(
                predicate: #Predicate<FoodEntry> { entry in
                    entry.loggedAt >= rangeStart &&
                    entry.loggedAt < rangeEnd &&
                    entry.pendingDeleteAt == nil
                },
                sortBy: [SortDescriptor(\.loggedAt)]
            )
            let foods = try context.fetch(foodDescriptor)

            let waterDescriptor = FetchDescriptor<WaterEntry>(
                predicate: #Predicate<WaterEntry> { entry in
                    entry.loggedAt >= rangeStart &&
                    entry.loggedAt < rangeEnd &&
                    entry.pendingDeleteAt == nil
                },
                sortBy: [SortDescriptor(\.loggedAt)]
            )
            let waters = try context.fetch(waterDescriptor)

            let weightDescriptor = FetchDescriptor<WeightEntry>(
                predicate: #Predicate<WeightEntry> { entry in
                    entry.loggedAt >= rangeStart &&
                    entry.loggedAt < rangeEnd &&
                    entry.pendingDeleteAt == nil
                },
                sortBy: [SortDescriptor(\.loggedAt)]
            )
            let weights = try context.fetch(weightDescriptor)

            let foodCSV = buildFoodCSV(from: foods)
            let waterCSV = buildWaterCSV(from: waters)
            let weightCSV = buildWeightCSV(from: weights)

            // v1.9 — energy.csv only when the toggle is on. Health reads are
            // async so we await them; the rest of the export stays sync.
            var energyCSV: String? = nil
            var energyDayCount: Int = 0
            if showCaloriesBurnedFromHealth {
                async let active = HealthService.readActiveEnergy(from: rangeStart, to: rangeEnd)
                async let basal  = HealthService.readBasalEnergy(from:  rangeStart, to: rangeEnd)
                let (activeMap, basalMap) = await (active, basal)
                let consumedMap = consumedByDay(foods)
                let result = buildEnergyCSV(active: activeMap, basal: basalMap, consumed: consumedMap)
                energyCSV = result.csv
                energyDayCount = result.dayCount
            }

            // Filename: FoodJournal-food-2026-04-03-to-2026-05-03.csv
            let dfFile = DateFormatter()
            dfFile.dateFormat = "yyyy-MM-dd"
            dfFile.locale = Locale(identifier: "en_US_POSIX")
            let startStr = dfFile.string(from: startDate)
            let endStr = dfFile.string(from: endDate)

            let tmp = FileManager.default.temporaryDirectory
            let foodURL = tmp.appendingPathComponent("FoodJournal-food-\(startStr)-to-\(endStr).csv")
            let waterURL = tmp.appendingPathComponent("FoodJournal-water-\(startStr)-to-\(endStr).csv")
            let weightURL = tmp.appendingPathComponent("FoodJournal-weight-\(startStr)-to-\(endStr).csv")
            let energyURL = tmp.appendingPathComponent("FoodJournal-energy-\(startStr)-to-\(endStr).csv")

            // Overwrite if a previous export with the same range is still in tmp
            try? FileManager.default.removeItem(at: foodURL)
            try? FileManager.default.removeItem(at: waterURL)
            try? FileManager.default.removeItem(at: weightURL)
            try? FileManager.default.removeItem(at: energyURL)

            try foodCSV.write(to: foodURL, atomically: true, encoding: .utf8)
            try waterCSV.write(to: waterURL, atomically: true, encoding: .utf8)
            try weightCSV.write(to: weightURL, atomically: true, encoding: .utf8)

            var items: [URL] = [foodURL, waterURL, weightURL]
            if let energyCSV {
                try energyCSV.write(to: energyURL, atomically: true, encoding: .utf8)
                items.append(energyURL)
            }
            shareItems = items

            var summary = "Prepared \(foods.count) food + \(waters.count) water + \(weights.count) weight entries."
            if energyCSV != nil {
                summary += " Energy: \(energyDayCount) day\(energyDayCount == 1 ? "" : "s")."
            }
            lastSummary = summary
            isGenerating = false
            isShareSheetPresented = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            isGenerating = false
        }
    }

    /// Sums each food entry's calories (scaled by servings) by calendar day.
    private func consumedByDay(_ foods: [FoodEntry]) -> [Date: Double] {
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for f in foods {
            let day = cal.startOfDay(for: f.loggedAt)
            out[day, default: 0] += f.calories * f.servings
        }
        return out
    }

    // MARK: - CSV builders

    private func buildFoodCSV(from entries: [FoodEntry]) -> String {
        let header: [String] = [
            "date", "time", "meal", "name", "brand", "source",
            "servings", "unit",
            "calories",
            "protein_g", "carbs_g", "fat_g",
            "fiber_g", "sugar_g",
            "saturated_fat_g", "polyunsaturated_fat_g", "monounsaturated_fat_g", "trans_fat_g",
            "cholesterol_mg", "sodium_mg", "potassium_mg",
            "vitamin_a_ug", "vitamin_c_mg", "vitamin_d_ug",
            "calcium_mg", "iron_mg", "magnesium_mg",
            "barcode"
        ]

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = [header.joined(separator: ",")]
        for e in entries {
            let s = e.servings  // multiply per-serving values to get totals
            let row: [String] = [
                dateFmt.string(from: e.loggedAt),
                timeFmt.string(from: e.loggedAt),
                csvEscape(e.mealType),
                csvEscape(e.name),
                csvEscape(e.brand ?? ""),
                csvEscape(e.source),
                num(e.servings),
                csvEscape(e.servingUnit),
                num(e.calories * s),
                num(e.protein * s),
                num(e.carbs * s),
                num(e.fat * s),
                numOpt(e.fiber, scaledBy: s),
                numOpt(e.sugar, scaledBy: s),
                numOpt(e.saturatedFat, scaledBy: s),
                numOpt(e.polyunsaturatedFat, scaledBy: s),
                numOpt(e.monounsaturatedFat, scaledBy: s),
                numOpt(e.transFat, scaledBy: s),
                numOpt(e.cholesterol, scaledBy: s),
                numOpt(e.sodium, scaledBy: s),
                numOpt(e.potassium, scaledBy: s),
                numOpt(e.vitaminA, scaledBy: s),
                numOpt(e.vitaminC, scaledBy: s),
                numOpt(e.vitaminD, scaledBy: s),
                numOpt(e.calcium, scaledBy: s),
                numOpt(e.iron, scaledBy: s),
                numOpt(e.magnesium, scaledBy: s),
                csvEscape(e.barcode ?? "")
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func buildWaterCSV(from entries: [WaterEntry]) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = ["date,time,amount_oz"]
        for e in entries {
            let row = [
                dateFmt.string(from: e.loggedAt),
                timeFmt.string(from: e.loggedAt),
                num(e.amountOz)
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per calendar day in the union of (active, basal, consumed)
    /// non-empty sets. Nil values render as empty cells — preserves nil ≠ 0.
    /// Returns (csv, dayCount) so the summary line can mention coverage.
    private func buildEnergyCSV(
        active: [Date: Double],
        basal: [Date: Double],
        consumed: [Date: Double]
    ) -> (csv: String, dayCount: Int) {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")

        let allDays = Set(active.keys).union(basal.keys).union(consumed.keys)
        let sortedDays = allDays.sorted()

        var lines: [String] = [
            "date,activeEnergyKcal,basalEnergyKcal,totalBurnedKcal,consumedKcal,netCaloriesKcal"
        ]
        for day in sortedDays {
            let a = active[day]
            let b = basal[day]
            let c = consumed[day]
            // Total burned = a + b when either present; nil only when both nil.
            let total: Double?
            switch (a, b) {
            case let (a?, b?): total = a + b
            case let (a?, nil): total = a
            case let (nil, b?): total = b
            case (nil, nil):   total = nil
            }
            // Net = consumed − total burned, only when both are known.
            let net: Double?
            if let c, let total { net = c - total } else { net = nil }

            let row = [
                dateFmt.string(from: day),
                a.map(num) ?? "",
                b.map(num) ?? "",
                total.map(num) ?? "",
                c.map(num) ?? "",
                net.map(num) ?? ""
            ].joined(separator: ",")
            lines.append(row)
        }
        return (lines.joined(separator: "\n") + "\n", sortedDays.count)
    }

    private func buildWeightCSV(from entries: [WeightEntry]) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = ["date,time,weight_lbs"]
        for e in entries {
            let row = [
                dateFmt.string(from: e.loggedAt),
                timeFmt.string(from: e.loggedAt),
                num(e.weightLbs)
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Formatting helpers

    /// Wrap a string in quotes only if it contains a comma, double-quote, or newline.
    /// Internal double-quotes get doubled per RFC 4180.
    private func csvEscape(_ s: String) -> String {
        if s.isEmpty { return "" }
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    /// Format a number compactly: keep up to 4 decimals, strip trailing zeros and orphan dot.
    private func num(_ d: Double) -> String {
        var s = String(format: "%.4f", d)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// nil → empty cell (NEVER 0). This is the "nil ≠ 0" invariant in CSV form.
    private func numOpt(_ d: Double?, scaledBy servings: Double) -> String {
        guard let d else { return "" }
        return num(d * servings)
    }
}

// MARK: - ShareSheet (UIKit bridge)
/// Wraps UIActivityViewController so SwiftUI's `.sheet` can present the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
