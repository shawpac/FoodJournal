import SwiftUI
import SwiftData

// MARK: - SearchSheet
/// Unified search across the local library and USDA FoodData Central.
/// Library results stream in instantly. USDA results follow after a 300ms debounce
/// so we don't hammer their API on every keystroke.
struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let defaultMeal: String?
        let defaultDate: Date?

        init(defaultMeal: String? = nil, defaultDate: Date? = nil) {
            self.defaultMeal = defaultMeal
            self.defaultDate = defaultDate
        }

    @State private var query: String = ""
    @State private var libraryResults: [LibraryFood] = []
    @State private var usdaResults: [USDAService.SearchHit] = []
    @State private var isLoadingUSDA = false
    @State private var usdaError: String?
    @State private var includeBranded = false

    /// Wraps a Prefill so it can be passed to .sheet(item:). Identifiable per-presentation,
    /// not per-food.
    private struct Pick: Identifiable {
        let id = UUID()
        let prefill: ConfirmFoodView.Prefill
    }
    @State private var pendingPick: Pick?

    /// Identifies the current in-flight USDA search so older searches can be ignored
    /// when the user keeps typing.
    @State private var searchToken: UUID = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                List {
                    if !libraryResults.isEmpty {
                        Section {
                            ForEach(libraryResults) { food in
                                LibraryRow(food: food) {
                                    pick(library: food)
                                }
                            }
                        } header: {
                            sectionHeader("Your library", systemImage: "books.vertical")
                        }
                    }

                    if isLoadingUSDA {
                        Section {
                            HStack {
                                ProgressView()
                                Text("Searching USDA…")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    if let usdaError {
                        Section {
                            Text(usdaError)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                    }

                    if !usdaResults.isEmpty {
                        Section {
                            ForEach(usdaResults) { hit in
                                USDARow(hit: hit) {
                                    pick(usda: hit)
                                }
                            }
                        } header: {
                            sectionHeader("USDA database", systemImage: "leaf")
                        } footer: {
                            Toggle("Include branded foods", isOn: $includeBranded)
                                .font(.footnote)
                                .onChange(of: includeBranded) { _, _ in
                                    runUSDASearch()
                                }
                        }
                    }

                    if shouldShowEmptyState {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                                Text("Type to search your foods or USDA's database.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .listRowBackground(Color.clear)
                        }
                    }

                    if shouldShowNoResults {
                        Section {
                            VStack(spacing: 6) {
                                Text("No results")
                                    .font(.headline)
                                Text("Try a different word, or log it manually.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                runLibrarySearch(newValue)
                debounceUSDASearch(newValue)
            }
            .sheet(item: $pendingPick) { pick in
                            NavigationStack {
                                ConfirmFoodView(prefill: pick.prefill, source: "search", defaultMeal: defaultMeal, defaultDate: defaultDate) {
                                    pendingPick = nil
                                    dismiss()
                                }
                    .navigationTitle("Confirm")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { pendingPick = nil }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search foods", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .textCase(nil)
    }

    // MARK: - Computed UI flags

    private var shouldShowEmptyState: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var shouldShowNoResults: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty
            && libraryResults.isEmpty
            && usdaResults.isEmpty
            && !isLoadingUSDA
            && usdaError == nil
    }

    // MARK: - Search execution

    private func runLibrarySearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            libraryResults = []
            return
        }
        libraryResults = LibraryService.search(trimmed, in: context)
    }

    private func debounceUSDASearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        usdaError = nil
        usdaResults = []
        guard !trimmed.isEmpty else {
            isLoadingUSDA = false
            return
        }

        let token = UUID()
        searchToken = token
        isLoadingUSDA = true

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard token == searchToken else { return }
            await performUSDASearch(query: trimmed, token: token)
        }
    }

    /// Re-runs the USDA query (used when the branded toggle flips).
    private func runUSDASearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let token = UUID()
        searchToken = token
        isLoadingUSDA = true
        usdaResults = []
        usdaError = nil

        Task {
            await performUSDASearch(query: trimmed, token: token)
        }
    }

    private func performUSDASearch(query q: String, token: UUID) async {
        do {
            let hits = try await USDAService.search(q, includeBranded: includeBranded)
            await MainActor.run {
                guard token == searchToken else { return }
                usdaResults = hits
                isLoadingUSDA = false
            }
        } catch {
            await MainActor.run {
                guard token == searchToken else { return }
                usdaError = error.localizedDescription
                isLoadingUSDA = false
            }
        }
    }

    // MARK: - Picking a result

    private func pick(library food: LibraryFood) {
        Haptic.light()
        pendingPick = Pick(prefill: LibraryService.toPrefill(food))
    }

    private func pick(usda hit: USDAService.SearchHit) {
        Haptic.light()
        pendingPick = Pick(prefill: hit.toPrefill())
    }
}

// MARK: - Rows

private struct LibraryRow: View {
    let food: LibraryFood
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if let brand = food.brand, !brand.isEmpty {
                            Text(brand)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        Text("\(Int(food.calories)) cal\(food.isPer100g ? "/100g" : "/serving")")
                        Text("·").foregroundStyle(.tertiary)
                        Text("used \(food.useCount)×")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct USDARow: View {
    let hit: USDAService.SearchHit
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(hit.dataType)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(typeColor.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(typeColor)
                        if let brand = hit.brand, !brand.isEmpty {
                            Text(brand).foregroundStyle(.secondary)
                        }
                        Text("\(Int(hit.caloriesPer100g)) cal/100g")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var typeColor: Color {
        switch hit.dataType {
        case "Foundation":     return .green
        case "SR Legacy":      return .blue
        case "Survey (FNDDS)": return .purple
        case "Branded":        return .orange
        default:               return .gray
        }
    }
}
