import SwiftUI
import SwiftData

// MARK: - SearchSheet
/// Unified search across the local library and USDA FoodData Central.
/// Library results stream in instantly. USDA results follow after a 300ms debounce
/// so we don't hammer their API on every keystroke.
///
/// v1.7.3: library rows now support a leading-edge swipe → "Quick add" action that
/// creates a FoodEntry directly with default amounts (100g for per-100g foods,
/// 1 serving for per-serving foods), no Confirm screen. Late-night warning still
/// fires for snacks in the configured window. 5-second undo toast.
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

    // MARK: Quick-add state (v1.7.3)
    /// The most recently added entry, undoable for 5 seconds. nil when no undo is active.
    @State private var pendingUndoEntry: FoodEntry?
    @State private var undoMessage: String?
    @State private var undoTask: Task<Void, Never>?

    // MARK: Late-night alert state
    @State private var pendingLateNightFood: LibraryFood?
    @State private var showLateNightAlert: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            quickAdd(food)
                                        } label: {
                                            Label("Quick add", systemImage: "plus.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                }
                            } header: {
                                sectionHeader("Your library", systemImage: "books.vertical")
                            } footer: {
                                Text("Swipe right → on a library row for quick-add (1 serving / 100g defaults, no confirm screen).")
                                    .font(.caption)
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

                // Quick-add undo toast (v1.7.3)
                if let undoMessage {
                    HStack(spacing: 12) {
                        Text(undoMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Undo") { undoQuickAdd() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: undoMessage)
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
            .alert("Late-night snack?", isPresented: $showLateNightAlert) {
                Button("Cancel", role: .cancel) {
                    pendingLateNightFood = nil
                }
                Button("Log it anyway") {
                    if let food = pendingLateNightFood {
                        commitQuickAdd(food)
                        pendingLateNightFood = nil
                    }
                }
            } message: {
                Text("It's getting late…")
            }
            .onDisappear {
                undoTask?.cancel()
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

    // MARK: - Quick add (v1.7.3)

    /// Triggered by the leading-edge swipe action on a library row.
    /// Checks late-night warning first; if triggered, defers commit until user confirms.
    private func quickAdd(_ food: LibraryFood) {
        Haptic.success()
        let meal = defaultMeal ?? MealTimeHelper.mealType()

        if MealTimeHelper.shouldWarnAboutLateSnack(meal: meal) {
            pendingLateNightFood = food
            showLateNightAlert = true
            return
        }

        commitQuickAdd(food)
    }

    /// Creates a FoodEntry from the LibraryFood with default amount (100g / 1 serving),
    /// inserts it into context, bumps useCount via LibraryFoodUpsert, and starts the
    /// 5-second undo timer. Mirrors ConfirmFoodView.save() with scale = 1.
    private func commitQuickAdd(_ food: LibraryFood) {
        let meal = defaultMeal ?? MealTimeHelper.mealType()
        let prefill = LibraryService.toPrefill(food)

        let entry = FoodEntry(
                    name: prefill.name,
                    brand: prefill.brand,
                    servings: 1,
                    servingUnit: "100g",
                    calories: prefill.caloriesPer100g,
                    protein: prefill.proteinPer100g,
                    carbs: prefill.carbsPer100g,
                    fat: prefill.fatPer100g,
                    saturatedFat: prefill.saturatedFatPer100g,
                    polyunsaturatedFat: prefill.polyunsaturatedFatPer100g,
                    monounsaturatedFat: prefill.monounsaturatedFatPer100g,
                    transFat: prefill.transFatPer100g,
                    fiber: prefill.fiberPer100g,
                    sugar: prefill.sugarPer100g,
                    cholesterol: prefill.cholesterolPer100g,
                    sodium: prefill.sodiumPer100g,
                    potassium: prefill.potassiumPer100g,
                    vitaminA: prefill.vitaminAPer100g,
                    vitaminC: prefill.vitaminCPer100g,
                    vitaminD: prefill.vitaminDPer100g,
                    calcium: prefill.calciumPer100g,
                    iron: prefill.ironPer100g,
                    magnesium: prefill.magnesiumPer100g,
                    mealType: meal,
                    source: "search-quick-add",
                    barcode: prefill.barcode
                )

        if let defaultDate {
            entry.loggedAt = defaultDate
        }

        context.insert(entry)
        LibraryFoodUpsert.upsert(from: entry, in: context)

        pendingUndoEntry = entry
        undoMessage = "Added \(food.name) to \(meal.capitalized)"

        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                pendingUndoEntry = nil
                undoMessage = nil
            }
        }
    }

    /// Removes the most recently added entry. Called from the undo toast button.
    private func undoQuickAdd() {
        Haptic.light()
        undoTask?.cancel()
        if let entry = pendingUndoEntry {
            context.delete(entry)
        }
        pendingUndoEntry = nil
        undoMessage = nil
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
