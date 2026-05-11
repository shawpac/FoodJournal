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
                }

    @State private var image: UIImage?
            @State private var estimate: ClaudeVisionService.Estimate?
            @State private var isAnalyzing = false
            @State private var errorMessage: String?
            @State private var mealType: String
            @State private var showingCamera = false
            @State private var showingLateSnackAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(maxHeight: 280)
                                                .clipShape(RoundedRectangle(cornerRadius: 16))

                                            // Show Analyze + Pick different photo buttons when we have an image
                                            // but haven't analyzed it yet (and aren't currently analyzing).
                                            if estimate == nil && !isAnalyzing {
                                                HStack(spacing: 8) {
                                                                                Button {
                                                                                    showingCamera = true
                                                                                } label: {
                                                                                    Text("Retake")
                                                                                        .font(.subheadline.weight(.medium))
                                                                                        .frame(maxWidth: .infinity)
                                                                                        .padding(.vertical, 12)
                                                                                        .background(Color(.secondarySystemGroupedBackground),
                                                                                                    in: RoundedRectangle(cornerRadius: 12))
                                                                                        .foregroundStyle(.primary)
                                                                                }
                                                                                .buttonStyle(.plain)

                                                                                Button {
                                                                                    Task { await analyze(image) }
                                                                                } label: {
                                                                                    Text("Analyze")
                                                                                        .font(.subheadline.weight(.semibold))
                                                                                        .frame(maxWidth: .infinity)
                                                                                        .padding(.vertical, 12)
                                                                                        .background(.pink, in: RoundedRectangle(cornerRadius: 12))
                                                                                        .foregroundStyle(.white)
                                                                                }
                                                                                .buttonStyle(.plain)
                                                                            }
                                            }
                    } else {
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

                                        if isAnalyzing {
                                            ProgressView("Asking Claude…")
                                                .padding(.top, 12)
                                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }

                    if let estimate {
                        EstimateCard(estimate: estimate)

                        Picker("Meal", selection: $mealType) {
                            Text("Breakfast").tag("breakfast")
                            Text("Lunch").tag("lunch")
                            Text("Dinner").tag("dinner")
                            Text("Snack").tag("snack")
                        }
                        .pickerStyle(.segmented)

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
                            if image == nil {
                                showingCamera = true
                            }
                        }
            .fullScreenCover(isPresented: $showingCamera) {
                                        CameraPicker(image: $image)
                                            .ignoresSafeArea()
                                            .onDisappear {
                                                // Clear stale estimate so the Analyze button reappears for the new photo.
                                                if estimate != nil { estimate = nil }
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
    private func analyze(_ img: UIImage) async {
            // Compute the hash first so we can check the cache.
            guard let prepared = ClaudeVisionService.prepareImage(img) else {
                errorMessage = "Could not encode image."
                return
            }
            let imageHash = prepared.hash

            // Cache hit?
            let descriptor = FetchDescriptor<CachedPhotoEstimate>(
                predicate: #Predicate { $0.imageHash == imageHash }
            )
            if let cached = try? context.fetch(descriptor).first {
                print("PhotoLogSheet: cache hit, skipping API call")
                estimate = cached.toEstimate()
                return
            }

            // Cache miss — go to the API.
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
                let result = try await ClaudeVisionService.estimate(image: img, apiKey: key)
                estimate = result

                // Save to cache so the same photo doesn't cost again next time.
                let cache = CachedPhotoEstimate(
                    imageHash: imageHash,
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
                            if let defaultDate {
                                entry.loggedAt = defaultDate
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
