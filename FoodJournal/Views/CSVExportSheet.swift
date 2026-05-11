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
                    Text("Generates three CSV files (food entries, water entries, weight entries) and opens the share sheet — email, save to Files, AirDrop to your Mac, etc.")
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

            // Overwrite if a previous export with the same range is still in tmp
            try? FileManager.default.removeItem(at: foodURL)
            try? FileManager.default.removeItem(at: waterURL)
            try? FileManager.default.removeItem(at: weightURL)

            try foodCSV.write(to: foodURL, atomically: true, encoding: .utf8)
            try waterCSV.write(to: waterURL, atomically: true, encoding: .utf8)
            try weightCSV.write(to: weightURL, atomically: true, encoding: .utf8)

            shareItems = [foodURL, waterURL, weightURL]
            lastSummary = "Prepared \(foods.count) food + \(waters.count) water + \(weights.count) weight entries."
            isGenerating = false
            isShareSheetPresented = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            isGenerating = false
        }
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
