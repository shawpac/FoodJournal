import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - LabPhotoImportSheet (Path B: photo/PDF → transcribe → REVIEW → save)
///
/// Mandatory human review. The flow:
///   1. User captures/picks a photo, picks a photo from the library, OR picks
///      a PDF (e.g. the direct PDF export from Apple Health → Browse →
///      Lab Results → Share → PDF).
///   2. ClaudeVisionService.extractLabReport(image:) or (pdfData:) transcribes
///      it (no interpretation).
///   3. ALL extracted rows populate an editable table — every field is
///      editable; rows can be deleted; new rows can be added.
///   4. A prominent "AI-extracted — verify against your report before saving"
///      banner sits at the top of the review surface.
///   5. Only the user's confirmed version persists to the LabPanel.
/// Nothing extracted by Claude is ever saved directly to SwiftData.
struct LabPhotoImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum Stage {
        case picking            // empty — user hasn't picked yet
        case extracting         // API call in flight
        case review             // editable extracted results, ready to save
    }

    @State private var stage: Stage = .picking
    @State private var pickedImage: UIImage?
    @State private var pickedPDF: Data?
    @State private var collectedDate: Date = .now
    @State private var source: String = ""
    @State private var rows: [ReviewRow] = []
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingPDFPicker = false

    /// A LabResult draft shown on the review surface. Fields are strings so
    /// edits stay free-form until commit; numeric parsing happens at save
    /// time, the same way LabPanelManualSheet handles it.
    struct ReviewRow: Identifiable {
        let id = UUID()
        var testName: String
        var valueStr: String
        var valueText: String
        var unit: String
        var refLowStr: String
        var refHighStr: String
        var refRangeText: String
    }

    private var canSave: Bool {
        stage == .review &&
        !source.trimmingCharacters(in: .whitespaces).isEmpty &&
        rows.contains(where: { !$0.testName.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .picking:
                    pickerForm
                case .extracting:
                    extractingForm
                case .review:
                    reviewForm
                }
            }
            .navigationTitle("Import lab report")
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
            .sheet(isPresented: $showingCamera) {
                CameraPicker(image: $pickedImage)
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $showingPDFPicker,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePDFPick(result)
            }
            .onChange(of: pickedImage) { _, newImage in
                guard newImage != nil else { return }
                Task { await analyzeImage() }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        pickedImage = img
                    }
                }
            }
        }
    }

    // MARK: - Stage views

    private var pickerForm: some View {
        Form {
            Section {
                Text("Photograph or pick a lab report — printed page, screenshot, or a PDF (the direct PDF export from Apple Health → Browse → Lab Results works). The app will transcribe the printed values; you REVIEW every row before anything is saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Pick from Photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    showingPDFPicker = true
                } label: {
                    Label("Pick a PDF", systemImage: "doc.richtext")
                }
            } footer: {
                Text("PDFs are read natively — multi-page reports go in one shot. Up to 32 MB / 100 pages.")
            }

            Section {
                Text("Transcription only. Claude is instructed not to interpret values, convert units, or invent reference ranges. If a field isn't on the page, it's left blank.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var extractingForm: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Transcribing the report…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("This is transcription only — no interpretation. You will review every value next.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var reviewForm: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("AI-extracted — verify against your report before saving.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Text("Every value, unit, and range below was read from a photo. Tap any field to correct, delete misread rows, or add ones the model missed. Saving commits only what's on this screen.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

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
                        Text(row.testName.isEmpty ? "Result" : row.testName)
                        Spacer()
                        Button(role: .destructive) {
                            if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                                rows.remove(at: idx)
                            }
                        } label: {
                            Text("Delete").font(.caption)
                        }
                    }
                }
            }

            Section {
                Button {
                    rows.append(ReviewRow(
                        testName: "",
                        valueStr: "",
                        valueText: "",
                        unit: "",
                        refLowStr: "",
                        refHighStr: "",
                        refRangeText: ""
                    ))
                } label: {
                    Label("Add a missed row", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Text("Reminder: only ranges PRINTED ON THE REPORT belong here. Don't paste in ranges from elsewhere — they would flag your results against a range that isn't your lab's.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Claude extraction (image + PDF entry points)

    @MainActor
    private func analyzeImage() async {
        guard let image = pickedImage else { return }
        await runExtraction(defaultSource: "Photo import") { key in
            try await ClaudeVisionService.extractLabReport(image: image, apiKey: key)
        } onFailure: {
            pickedImage = nil
        }
    }

    @MainActor
    private func analyzePDF() async {
        guard let pdf = pickedPDF else { return }
        await runExtraction(defaultSource: "PDF import") { key in
            try await ClaudeVisionService.extractLabReport(pdfData: pdf, apiKey: key)
        } onFailure: {
            pickedPDF = nil
        }
    }

    /// Shared post-extract handling: pre-fill panel metadata, map extracted
    /// results into editable review rows, land on the review stage.
    @MainActor
    private func runExtraction(
        defaultSource: String,
        call: (String) async throws -> ClaudeVisionService.ExtractedLabReport,
        onFailure: () -> Void
    ) async {
        stage = .extracting
        errorMessage = nil
        let key = KeychainStore.loadAPIKey()
        guard !key.isEmpty else {
            errorMessage = "Add your Anthropic API key in Settings first."
            stage = .picking
            onFailure()
            return
        }
        do {
            let extracted = try await call(key)
            if let dateStr = extracted.collected_date,
               let date = parseExtractedDate(dateStr) {
                collectedDate = date
            }
            if let s = extracted.source, !s.isEmpty {
                source = s
            } else if source.isEmpty {
                source = defaultSource
            }
            rows = extracted.results.map { r in
                ReviewRow(
                    testName: r.test_name,
                    valueStr: r.value.map { formatExtractedDouble($0) } ?? "",
                    valueText: r.value_text ?? "",
                    unit: r.unit ?? "",
                    refLowStr: r.ref_range_low.map { formatExtractedDouble($0) } ?? "",
                    refHighStr: r.ref_range_high.map { formatExtractedDouble($0) } ?? "",
                    refRangeText: r.ref_range_text ?? ""
                )
            }
            stage = .review
        } catch {
            errorMessage = error.localizedDescription
            stage = .picking
            onFailure()
        }
    }

    // MARK: - PDF picker handoff

    private func handlePDFPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // The picked file lives outside our sandbox (Files / iCloud Drive);
            // grab a security-scoped resource just like CSVImportSheet does.
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pickedPDF = data
                Task { await analyzePDF() }
            } catch {
                errorMessage = "Couldn't read that PDF: \(error.localizedDescription)"
            }
        case .failure(let error):
            errorMessage = "Picker error: \(error.localizedDescription)"
        }
    }

    // MARK: - Save (commits only the reviewed version)

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

// MARK: - File-private helpers

private func parseExtractedDate(_ s: String) -> Date? {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.locale = Locale(identifier: "en_US_POSIX")
    return fmt.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func formatExtractedDouble(_ v: Double) -> String {
    if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
    return String(format: "%g", v)
}

private func emptyToNil(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

private func emptyToDouble(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : Double(t)
}
