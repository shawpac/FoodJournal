import SwiftUI
import PhotosUI
import SwiftData

struct PhotoLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var estimate: ClaudeVisionService.Estimate?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var mealType = "snack"

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
                    } else {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 44))
                                Text("Choose a photo of your meal")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 16))
                        }
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
                            saveEntry(estimate)
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
            .onChange(of: selectedItem) { _, newItem in
                Task { await loadImage(newItem) }
            }
        }
    }

    private func loadImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                image = img
                await analyze(img)
            }
        } catch {
            errorMessage = "Could not load image: \(error.localizedDescription)"
        }
    }

    private func analyze(_ img: UIImage) async {
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
                    estimate = try await ClaudeVisionService.estimate(image: img, apiKey: key)
                } catch let serviceError as ClaudeVisionService.ServiceError {
                    errorMessage = serviceError.errorDescription ?? "Unknown error"
                } catch {
                    errorMessage = "Estimate failed: \(error.localizedDescription)"
                }
    }

    private func saveEntry(_ e: ClaudeVisionService.Estimate) {
        let entry = FoodEntry(
            name: e.name,
            servings: e.servings,
            servingUnit: e.serving_unit,
            calories: e.calories,
            protein: e.protein,
            carbs: e.carbs,
            fat: e.fat,
            mealType: mealType,
            source: "photo"
        )
        context.insert(entry)
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
                stat("kcal", "\(Int(estimate.calories))")
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
