import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - CSVImportSheet
/// v2.0.1 — Inverse of CSVExportSheet. Restores food / water / weight history
/// after a reinstall. APPEND-ONLY with an EMPTY-TABLE GUARD per type: each
/// of FoodEntry / WaterEntry / WeightEntry must be empty (no non-soft-deleted
/// rows) before its CSV will be accepted. There is no dedupe/merge — by
/// design, since the user's usage contract is "only import into a fresh
/// reinstall."
///
/// Schemas mirror CSVExportSheet exactly:
/// - food.csv:   date,time,meal,name,brand,source,servings,unit,calories,
///               protein_g,carbs_g,fat_g,fiber_g,sugar_g,saturated_fat_g,
///               polyunsaturated_fat_g,monounsaturated_fat_g,trans_fat_g,
///               cholesterol_mg,sodium_mg,potassium_mg,vitamin_a_ug,
///               vitamin_c_mg,vitamin_d_ug,calcium_mg,iron_mg,magnesium_mg,
///               barcode
///   Exporter writes TOTALS (per-serving × servings). Importer divides back
///   by servings to recover per-serving values for storage.
/// - water.csv:  date,time,amount_oz
/// - weight.csv: date,time,weight_lbs
///
/// Dates: yyyy-MM-dd (POSIX). Times: HH:mm (POSIX). RFC 4180 quoting.
/// Empty cell on an optional nutrient → nil. Empty cell on a required field
/// (name, loggedAt, amountOz, weightLbs, servings, calories) → row counted
/// as malformed and skipped.
struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var results: [ImportResult] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isPickerPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            if isImporting {
                                ProgressView()
                                Text("Importing…")
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                Text("Pick CSV files")
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isImporting)
                } footer: {
                    Text("Restores data from food.csv / water.csv / weight.csv exports. Pick any subset. Each type can only be imported into an empty database — if entries of that type already exist, the file is skipped. Use this only on a freshly reinstalled app.")
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.fileName)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(result.summary)
                                    .font(.callout)
                                    .foregroundStyle(result.color)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Import data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                allowsMultipleSelection: true
            ) { pickerResult in
                switch pickerResult {
                case .success(let urls):
                    Task { await importAll(urls) }
                case .failure(let error):
                    results.append(ImportResult(
                        fileName: "—",
                        summary: "Picker error: \(error.localizedDescription)",
                        color: .red
                    ))
                }
            }
        }
    }

    // MARK: - Driver

    private func importAll(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            await importOne(at: url)
        }
        Haptic.light()
    }

    private func importOne(at url: URL) async {
        let fileName = url.lastPathComponent

        // The picked file lives outside our sandbox (Files / iCloud Drive /
        // AirDropped to Files) so we must request security-scoped access.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            append(.init(
                fileName: fileName,
                summary: "Could not read file as UTF-8 text.",
                color: .red
            ))
            return
        }

        // Lines can be separated by \n or \r\n — split on either.
        let rawLines = text.split(omittingEmptySubsequences: true,
                                  whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
        guard let header = rawLines.first else {
            append(.init(fileName: fileName, summary: "Empty file.", color: .red))
            return
        }

        let kind = detectKind(headerLine: header)
        let dataLines = Array(rawLines.dropFirst())

        switch kind {
        case .food:
            await importFood(fileName: fileName, dataLines: dataLines)
        case .water:
            await importWater(fileName: fileName, dataLines: dataLines)
        case .weight:
            await importWeight(fileName: fileName, dataLines: dataLines)
        case .energy:
            append(.init(
                fileName: fileName,
                summary: "Energy data is read live from Apple Health and not stored locally. Nothing to import.",
                color: .secondary
            ))
        case .unknown:
            append(.init(
                fileName: fileName,
                summary: "Unrecognized CSV header. Expected food, water, or weight export.",
                color: .red
            ))
        }
    }

    private func append(_ result: ImportResult) {
        results.append(result)
    }

    // MARK: - Kind detection

    private enum FileKind { case food, water, weight, energy, unknown }

    /// Header-sniff. Filename is unreliable (user may rename); the first row
    /// of every export is a known string written by CSVExportSheet, so we
    /// match on prefix / exact string.
    private func detectKind(headerLine: String) -> FileKind {
        let normalized = headerLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("date,time,meal,name") { return .food }
        if normalized == "date,time,amount_oz"         { return .water }
        if normalized == "date,time,weight_lbs"        { return .weight }
        if normalized.hasPrefix("date,activeenergykcal") { return .energy }
        return .unknown
    }

    // MARK: - Food importer

    private func importFood(fileName: String, dataLines: [String]) async {
        if foodTableHasData() {
            append(.init(
                fileName: fileName,
                summary: "Food entries already exist in this app. Import skipped — import only into a freshly reinstalled app.",
                color: .orange
            ))
            return
        }

        var imported = 0
        var malformed = 0
        for raw in dataLines {
            let fields = parseCSVLine(raw)
            // 28 columns expected (see header in CSVExportSheet.buildFoodCSV)
            guard fields.count >= 28 else { malformed += 1; continue }

            // Column indices match the exporter's header order EXACTLY:
            //  0 date, 1 time, 2 meal, 3 name, 4 brand, 5 source,
            //  6 servings, 7 unit, 8 calories,
            //  9 protein_g, 10 carbs_g, 11 fat_g,
            // 12 fiber_g, 13 sugar_g,
            // 14 sat_fat, 15 poly_fat, 16 mono_fat, 17 trans_fat,
            // 18 cholesterol, 19 sodium, 20 potassium,
            // 21 vit_a, 22 vit_c, 23 vit_d,
            // 24 calcium, 25 iron, 26 magnesium,
            // 27 barcode
            guard let loggedAt = parseDateTime(date: fields[0], time: fields[1]) else {
                malformed += 1; continue
            }
            let name = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { malformed += 1; continue }
            guard let servings = parseRequiredDouble(fields[6]), servings > 0 else {
                malformed += 1; continue
            }
            guard let totalCal = parseRequiredDouble(fields[8]),
                  let totalProtein = parseRequiredDouble(fields[9]),
                  let totalCarbs   = parseRequiredDouble(fields[10]),
                  let totalFat     = parseRequiredDouble(fields[11])
            else { malformed += 1; continue }

            // Exporter wrote TOTALS = per-serving × servings. Invert: divide
            // by servings to recover the per-serving values the model stores.
            let s = servings
            let entry = FoodEntry(
                name: name,
                brand: emptyToNil(fields[4]),
                servings: servings,
                servingUnit: fields[7].isEmpty ? "serving" : fields[7],
                calories: totalCal / s,
                protein:  totalProtein / s,
                carbs:    totalCarbs / s,
                fat:      totalFat / s,
                saturatedFat:        parseOptionalDouble(fields[14]).map { $0 / s },
                polyunsaturatedFat:  parseOptionalDouble(fields[15]).map { $0 / s },
                monounsaturatedFat:  parseOptionalDouble(fields[16]).map { $0 / s },
                transFat:            parseOptionalDouble(fields[17]).map { $0 / s },
                fiber:               parseOptionalDouble(fields[12]).map { $0 / s },
                sugar:               parseOptionalDouble(fields[13]).map { $0 / s },
                cholesterol:         parseOptionalDouble(fields[18]).map { $0 / s },
                sodium:              parseOptionalDouble(fields[19]).map { $0 / s },
                potassium:           parseOptionalDouble(fields[20]).map { $0 / s },
                vitaminA:            parseOptionalDouble(fields[21]).map { $0 / s },
                vitaminC:            parseOptionalDouble(fields[22]).map { $0 / s },
                vitaminD:            parseOptionalDouble(fields[23]).map { $0 / s },
                calcium:             parseOptionalDouble(fields[24]).map { $0 / s },
                iron:                parseOptionalDouble(fields[25]).map { $0 / s },
                magnesium:           parseOptionalDouble(fields[26]).map { $0 / s },
                loggedAt: loggedAt,
                mealType: fields[2].isEmpty ? "snack" : fields[2],
                // Preserve the original source from the CSV (column 5) so
                // provenance survives a reinstall+import — keeps things like
                // EntryRow's sparkles icon for source=="suggestion" intact.
                // Only fall back to "import" when the source cell is empty
                // (e.g. hand-edited CSV missing the column value).
                source: emptyToNil(fields[5]) ?? "import",
                barcode: emptyToNil(fields[27])
            )
            context.insert(entry)
            // Maintain the personal library + useCount, same as every other
            // save path. Without this, imported foods wouldn't show up in
            // Most Used / Search ranking until the user re-logged them.
            LibraryFoodUpsert.upsert(from: entry, in: context)
            // Deliberately NO HealthSync.onFoodSaved here. Imported entries
            // are historical restorations, not new logs — re-writing them
            // to Apple Health would duplicate samples (when the original
            // export came from a Health-synced session) or orphan them
            // (when later deletes fire and the sample didn't exist).
            imported += 1
        }
        append(makeSummary(fileName: fileName, type: "food",
                           imported: imported, malformed: malformed))
    }

    // MARK: - Water importer

    private func importWater(fileName: String, dataLines: [String]) async {
        if waterTableHasData() {
            append(.init(
                fileName: fileName,
                summary: "Water entries already exist in this app. Import skipped — import only into a freshly reinstalled app.",
                color: .orange
            ))
            return
        }
        var imported = 0
        var malformed = 0
        for raw in dataLines {
            let fields = parseCSVLine(raw)
            guard fields.count >= 3 else { malformed += 1; continue }
            guard let loggedAt = parseDateTime(date: fields[0], time: fields[1]) else {
                malformed += 1; continue
            }
            guard let amountOz = parseRequiredDouble(fields[2]) else {
                malformed += 1; continue
            }
            let entry = WaterEntry(amountOz: amountOz, loggedAt: loggedAt)
            context.insert(entry)
            // No HealthSync — historical restoration only.
            imported += 1
        }
        append(makeSummary(fileName: fileName, type: "water",
                           imported: imported, malformed: malformed))
    }

    // MARK: - Weight importer

    private func importWeight(fileName: String, dataLines: [String]) async {
        if weightTableHasData() {
            append(.init(
                fileName: fileName,
                summary: "Weight entries already exist in this app. Import skipped — import only into a freshly reinstalled app.",
                color: .orange
            ))
            return
        }
        var imported = 0
        var malformed = 0
        for raw in dataLines {
            let fields = parseCSVLine(raw)
            guard fields.count >= 3 else { malformed += 1; continue }
            guard let loggedAt = parseDateTime(date: fields[0], time: fields[1]) else {
                malformed += 1; continue
            }
            guard let weightLbs = parseRequiredDouble(fields[2]) else {
                malformed += 1; continue
            }
            let entry = WeightEntry(weightLbs: weightLbs, loggedAt: loggedAt)
            context.insert(entry)
            // No HealthSync — historical restoration only.
            imported += 1
        }
        append(makeSummary(fileName: fileName, type: "weight",
                           imported: imported, malformed: malformed))
    }

    // MARK: - Empty-table guards

    /// True if any non-soft-deleted FoodEntry exists. Uses a fetchLimit so we
    /// don't load the whole table just to count.
    private func foodTableHasData() -> Bool {
        var d = FetchDescriptor<FoodEntry>(
            predicate: #Predicate<FoodEntry> { $0.pendingDeleteAt == nil }
        )
        d.fetchLimit = 1
        return ((try? context.fetch(d).count) ?? 0) > 0
    }

    private func waterTableHasData() -> Bool {
        var d = FetchDescriptor<WaterEntry>(
            predicate: #Predicate<WaterEntry> { $0.pendingDeleteAt == nil }
        )
        d.fetchLimit = 1
        return ((try? context.fetch(d).count) ?? 0) > 0
    }

    private func weightTableHasData() -> Bool {
        var d = FetchDescriptor<WeightEntry>(
            predicate: #Predicate<WeightEntry> { $0.pendingDeleteAt == nil }
        )
        d.fetchLimit = 1
        return ((try? context.fetch(d).count) ?? 0) > 0
    }

    // MARK: - Parsers

    /// Parses a single CSV line per RFC 4180 quoting rules. Handles embedded
    /// commas in quoted fields and escaped quotes (`""` inside a quoted field
    /// → a literal `"`). Multi-line quoted fields are NOT supported — the
    /// exporter only emits newlines as record separators because food names
    /// can't contain them via the UI.
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    /// Combines a date string (yyyy-MM-dd) and a time string (HH:mm) into a
    /// single Date. Returns nil if either parses fail. Matches the exporter's
    /// formatters byte-for-byte (POSIX locale).
    private func parseDateTime(date: String, time: String) -> Date? {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        let dTrim = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let tTrim = time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let day = dateFmt.date(from: dTrim),
              let t = timeFmt.date(from: tTrim) else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(
            bySettingHour: comps.hour ?? 12,
            minute: comps.minute ?? 0,
            second: 0,
            of: day
        )
    }

    /// Required numeric parser: nil if empty OR unparseable. Caller treats
    /// nil as "malformed row, skip" — never as a 0 substitute.
    private func parseRequiredDouble(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }

    /// Optional numeric parser: nil for empty OR unparseable. THIS is the
    /// nil ≠ 0 invariant in code form — a blank optional cell becomes
    /// Double? = nil, never 0. Do not change this to default to 0.
    private func parseOptionalDouble(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }

    private func emptyToNil(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Summaries

    private func makeSummary(fileName: String, type: String, imported: Int, malformed: Int) -> ImportResult {
        if imported == 0 && malformed == 0 {
            return ImportResult(
                fileName: fileName,
                summary: "No \(type) rows found in file.",
                color: .secondary
            )
        }
        var parts: [String] = []
        parts.append("Imported \(imported) \(type) \(imported == 1 ? "entry" : "entries").")
        if malformed > 0 {
            parts.append("Skipped \(malformed) malformed row\(malformed == 1 ? "" : "s").")
        }
        return ImportResult(
            fileName: fileName,
            summary: parts.joined(separator: " "),
            color: malformed > 0 ? .orange : .green
        )
    }

    // MARK: - Result model

    struct ImportResult: Identifiable {
        let id = UUID()
        let fileName: String
        let summary: String
        let color: Color
    }
}
