import SwiftUI
import SwiftData

struct PhotoLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let defaultMeal: String?
    let defaultDate: Date?

    init(defaultMeal: String? = nil, defaultDate: Date? = nil) {
        self.defaultMeal = defaultMeal
        self.defaultDate = defaultDate
        _mealType = State(initialValue: defaultMeal ?? MealTimeHelper.mealType())
        _pastDayLoggedAt = State(initialValue: defaultDate ?? .now)
    }

    /// User can attach up to this many angles. Higher values increase token cost
    /// per analyze call without much accuracy lift in practice.
    private let maxPhotos = 3

    @State private var images: [UIImage] = []
    /// v2.2.2 — optional typed context the user attaches to the photo set
    /// (weight, brand, prep notes). Folded into both the prompt and the
    /// cache hash so the same photo with different context misses cache.
    @State private var userContext: String = ""
    /// Camera writes here; .onDisappear transfers into `images` so the picker
    /// itself doesn't need to know about the array.
    @State private var newPhotoBuffer: UIImage?

    @State private var estimate: ClaudeVisionService.Estimate?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var mealType: String
    @State private var showingCamera = false
    @State private var showingLateSnackAlert = false
    /// Editable timestamp shown only when logging to a past day.
    @State private var pastDayLoggedAt: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if images.isEmpty {
                        takePhotoCTA
                    } else {
                        photoStrip

                        // v2.2.2 — context field. Stays visible during and
                        // after analysis so the user can refine and Re-analyze
                        // with new context.
                        contextField

                        if isAnalyzing {
                            ProgressView("Asking Claude…")
                                .padding(.top, 12)
                        } else if estimate == nil {
                            analyzeButton
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }

                    if let estimate {
                        if estimate.confidence.lowercased() == "low" {
                            lowConfidenceCard
                        }

                        EstimateCard(estimate: estimate)

                        Picker("Meal", selection: $mealType) {
                            Text("Breakfast").tag("breakfast")
                            Text("Lunch").tag("lunch")
                            Text("Dinner").tag("dinner")
                            Text("Snack").tag("snack")
                        }
                        .pickerStyle(.segmented)

                        if defaultDate != nil {
                            HStack {
                                Text("Time logged")
                                    .font(.subheadline)
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: $pastDayLoggedAt,
                                    in: ...Date.now,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            attemptSave(estimate)
                        } label: {
                            Text("Log this")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle("Photo log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if images.isEmpty {
                    showingCamera = true
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $newPhotoBuffer)
                    .ignoresSafeArea()
                    .onDisappear {
                        if let img = newPhotoBuffer, images.count < maxPhotos {
                            images.append(img)
                            // Stale estimate — fresh photo set means re-analyze.
                            if estimate != nil { estimate = nil }
                        }
                        newPhotoBuffer = nil
                    }
            }
            .alert("Late-night snack?", isPresented: $showingLateSnackAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log it anyway") {
                    if let e = estimate { saveEntry(e) }
                }
            } message: {
                Text("It's getting late. Eating this close to bed can affect sleep quality and digestion. Consider whether you really need it.")
            }
        }
    }

    // MARK: - Subviews

    private var takePhotoCTA: some View {
        Button {
            showingCamera = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44))
                Text("Take a photo of your meal")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { idx, img in
                    photoThumb(img: img, index: idx)
                }
                if images.count < maxPhotos {
                    Button {
                        showingCamera = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.title2)
                            Text("Add angle")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 110, height: 110)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func photoThumb(img: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                images.remove(at: index)
                if estimate != nil { estimate = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.75))
            }
            .padding(4)
        }
    }

    /// Multi-line context field. The user types weights, brands, prep
    /// notes — anything that helps Claude estimate accurately. Optional;
    /// leaving it blank preserves the v1.8.5 behavior exactly (including
    /// the cache hash, so prior cached estimates still hit).
    private var contextField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                Text("Add context (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            TextField(
                "e.g. \"6 oz chicken breast, grilled\" or \"weighs 200g\"",
                text: $userContext,
                axis: .vertical
            )
            .lineLimit(2...5)
            .textInputAutocapitalization(.sentences)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 10))
            Text("Claude will treat your text as authoritative — use it for weights, brands, or prep details the photo can't show.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var analyzeButton: some View {
        Button {
            Task { await analyze(force: false) }
        } label: {
            Text("Analyze \(images.count == 1 ? "photo" : "\(images.count) photos")")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.pink, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var lowConfidenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Low confidence")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Claude flagged this estimate as uncertain. Add another angle or re-analyze to try again.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if images.count < maxPhotos {
                    Button {
                        showingCamera = true
                    } label: {
                        Text("Add angle")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    Task { await analyze(force: true) }
                } label: {
                    Text("Re-analyze")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.orange, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Analyze

    /// Calls Claude with the current image set. When `force` is true, bypasses
    /// the on-device CachedPhotoEstimate cache so the user gets a fresh sample —
    /// used by the low-confidence "Re-analyze" button. The cache entry is
    /// updated in place on success.
    private func analyze(force: Bool) async {
        guard !images.isEmpty else {
            errorMessage = "Take a photo first."
            return
        }
        // v2.2.2 — fold the user context into the cache hash so the same
        // photo with different context misses cache and re-queries Claude.
        // Empty context falls through to the v1.8.5 hash unchanged.
        guard let prepared = ClaudeVisionService.prepareImages(images, userContext: userContext) else {
            errorMessage = "Could not encode image(s)."
            return
        }
        let cacheKey = prepared.hash

        if !force {
            let descriptor = FetchDescriptor<CachedPhotoEstimate>(
                predicate: #Predicate { $0.imageHash == cacheKey }
            )
            if let cached = try? context.fetch(descriptor).first {
                print("PhotoLogSheet: cache hit, skipping API call")
                estimate = cached.toEstimate()
                return
            }
        }

        let key = KeychainStore.loadAPIKey()
        guard !key.isEmpty else {
            errorMessage = "Add your Anthropic API key in Settings first."
            return
        }
        isAnalyzing = true
        errorMessage = nil
        estimate = nil
        defer { isAnalyzing = false }
        do {
            let result = try await ClaudeVisionService.estimate(images: images, userContext: userContext, apiKey: key)
            estimate = result

            // Upsert the cache. Re-analyze hits the existing-row branch and
            // overwrites in place so the next cache hit reflects the new result.
            let descriptor = FetchDescriptor<CachedPhotoEstimate>(
                predicate: #Predicate { $0.imageHash == cacheKey }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.name = result.name
                existing.servings = result.servings
                existing.servingUnit = result.serving_unit
                existing.calories = result.calories
                existing.protein = result.protein
                existing.carbs = result.carbs
                existing.fat = result.fat
                existing.saturatedFat = result.saturated_fat
                existing.polyunsaturatedFat = result.polyunsaturated_fat
                existing.monounsaturatedFat = result.monounsaturated_fat
                existing.transFat = result.trans_fat
                existing.fiber = result.fiber
                existing.sugar = result.sugar
                existing.cholesterol = result.cholesterol
                existing.sodium = result.sodium
                existing.potassium = result.potassium
                existing.vitaminA = result.vitamin_a
                existing.vitaminC = result.vitamin_c
                existing.vitaminD = result.vitamin_d
                existing.calcium = result.calcium
                existing.iron = result.iron
                existing.magnesium = result.magnesium
                existing.confidence = result.confidence
                existing.notes = result.notes
                existing.cachedAt = .now
            } else {
                let cache = CachedPhotoEstimate(
                    imageHash: cacheKey,
                    name: result.name,
                    servings: result.servings,
                    servingUnit: result.serving_unit,
                    calories: result.calories,
                    protein: result.protein,
                    carbs: result.carbs,
                    fat: result.fat,
                    saturatedFat: result.saturated_fat,
                    polyunsaturatedFat: result.polyunsaturated_fat,
                    monounsaturatedFat: result.monounsaturated_fat,
                    transFat: result.trans_fat,
                    fiber: result.fiber,
                    sugar: result.sugar,
                    cholesterol: result.cholesterol,
                    sodium: result.sodium,
                    potassium: result.potassium,
                    vitaminA: result.vitamin_a,
                    vitaminC: result.vitamin_c,
                    vitaminD: result.vitamin_d,
                    calcium: result.calcium,
                    iron: result.iron,
                    magnesium: result.magnesium,
                    confidence: result.confidence,
                    notes: result.notes
                )
                context.insert(cache)
            }
        } catch let serviceError as ClaudeVisionService.ServiceError {
            errorMessage = serviceError.errorDescription ?? "Unknown error"
        } catch {
            errorMessage = "Estimate failed: \(error.localizedDescription)"
        }
    }

    private func attemptSave(_ e: ClaudeVisionService.Estimate) {
        if MealTimeHelper.shouldWarnAboutLateSnack(meal: mealType) {
            showingLateSnackAlert = true
        } else {
            saveEntry(e)
        }
    }

    private func saveEntry(_ e: ClaudeVisionService.Estimate) {
        dismissKeyboard()
        Haptic.success()
        let entry = FoodEntry(
            name: e.name,
            servings: e.servings,
            servingUnit: e.serving_unit,
            calories: e.calories,
            protein: e.protein,
            carbs: e.carbs,
            fat: e.fat,
            saturatedFat: e.saturated_fat,
            polyunsaturatedFat: e.polyunsaturated_fat,
            monounsaturatedFat: e.monounsaturated_fat,
            transFat: e.trans_fat,
            fiber: e.fiber,
            sugar: e.sugar,
            cholesterol: e.cholesterol,
            sodium: e.sodium,
            potassium: e.potassium,
            vitaminA: e.vitamin_a,
            vitaminC: e.vitamin_c,
            vitaminD: e.vitamin_d,
            calcium: e.calcium,
            iron: e.iron,
            magnesium: e.magnesium,
            mealType: mealType,
            source: "photo"
        )
        if defaultDate != nil {
            entry.loggedAt = pastDayLoggedAt
        }
        context.insert(entry)
        LibraryFoodUpsert.upsert(from: entry, in: context)
        HealthSync.onFoodSaved(entry)
        dismiss()
    }
}

private struct EstimateCard: View {
    let estimate: ClaudeVisionService.Estimate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(estimate.name).font(.headline)
                Spacer()
                Text(estimate.confidence.uppercased())
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(confidenceColor.opacity(0.2),
                                in: Capsule())
                    .foregroundStyle(confidenceColor)
            }

            HStack(spacing: 16) {
                stat("cal", "\(Int(estimate.calories))")
                stat("P",    "\(Int(estimate.protein))g")
                stat("C",    "\(Int(estimate.carbs))g")
                stat("F",    "\(Int(estimate.fat))g")
            }

            if let notes = estimate.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var confidenceColor: Color {
        switch estimate.confidence.lowercased() {
        case "high":   return .green
        case "medium": return .orange
        default:       return .red
        }
    }
}

// MARK: - CameraPicker
// Wraps UIImagePickerController so SwiftUI can present the system camera UI.
// Camera is only available on real devices, never on the simulator — that's
// expected, and our Add tab already requires a real device for the barcode scanner.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
