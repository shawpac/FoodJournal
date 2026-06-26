import SwiftUI
import SwiftData

// MARK: - SearchSheet
/// Unified search across the local library + USDA FoodData Central + Open Food
/// Facts. Library results stream in instantly. Remote sources (USDA + OFF) run
/// concurrently after a 300ms debounce on the same keystroke; one failing
/// source doesn't block the other.
///
/// v1.7.3 — library rows have a leading-edge swipe → "Quick add" action that
///   creates a FoodEntry directly (100g / 1 serving defaults), no Confirm.
/// v2.2.1 — OFF is now a text-search source (was barcode-only). USDA + OFF
///   are merged into one ranked list with per-row source tags. Cross-source
///   dedupe collapses near-duplicates, preferring USDA on collisions. The
///   existing "Include branded foods" toggle now gates both USDA Branded
///   AND all OFF results (OFF is almost entirely branded).
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
    /// Merged USDA + OFF results, deduped, ranked by relevance. See
    /// `mergeAndDedupe(_:_:query:)` for the heuristic.
    @State private var remoteResults: [MergedHit] = []
    @State private var isLoadingRemote = false
    /// Surfaces only when BOTH USDA and OFF errored. A single source erroring
    /// is silently tolerated — partial coverage beats no coverage.
    @State private var remoteError: String?
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
    /// Reference to the current debounce + remote-fetch Task. When a new
    /// keystroke arrives we explicitly cancel this, which propagates down
    /// through Swift structured concurrency to the URLSession.data() call —
    /// the underlying URLSessionTask is cancelled instead of being left
    /// in-flight. Fixes a "nginx 400" symptom from api.data.gov when fast
    /// typing fires multiple rapid USDA requests over the same HTTP/2
    /// connection.
    @State private var remoteFetchTask: Task<Void, Never>?

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

                        if isLoadingRemote {
                            Section {
                                HStack {
                                    ProgressView()
                                    Text("Searching food databases…")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }

                        if let remoteError {
                            Section {
                                Text(remoteError)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }
                        }

                        if !remoteResults.isEmpty {
                            Section {
                                ForEach(remoteResults) { hit in
                                    MergedRow(hit: hit) {
                                        pick(merged: hit)
                                    }
                                }
                            } header: {
                                sectionHeader("Food databases", systemImage: "leaf")
                            } footer: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle("Include branded foods", isOn: $includeBranded)
                                        .font(.footnote)
                                        .onChange(of: includeBranded) { _, _ in
                                            runRemoteSearch()
                                        }
                                    Text("Branded toggle gates USDA Branded + Open Food Facts. USDA is lab-analyzed; OFF is crowd-sourced (denser branded coverage, more often partial).")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        if shouldShowEmptyState {
                            Section {
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundStyle(.tertiary)
                                    Text("Type to search your foods, USDA, or Open Food Facts.")
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
                debounceRemoteSearch(newValue)
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
            && remoteResults.isEmpty
            && !isLoadingRemote
            && remoteError == nil
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

    /// Schedule a remote (USDA + OFF) search 300ms after the last keystroke.
    /// Cancels any in-flight fetch so rapid typing doesn't pile up
    /// concurrent HTTPS requests on the same connection (which was triggering
    /// nginx 400s from api.data.gov).
    private func debounceRemoteSearch(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        remoteError = nil
        remoteResults = []

        // Cancel any prior debounce / fetch — propagates through Swift
        // structured concurrency to the URLSession data tasks inside.
        remoteFetchTask?.cancel()

        guard !trimmed.isEmpty else {
            isLoadingRemote = false
            return
        }

        let token = UUID()
        searchToken = token
        isLoadingRemote = true

        remoteFetchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            if Task.isCancelled { return }
            guard token == searchToken else { return }
            await performRemoteSearch(query: trimmed, token: token)
        }
    }

    /// Re-runs the remote query without debouncing (used when the Branded
    /// toggle flips — the user is explicitly changing scope, not typing).
    private func runRemoteSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Same cancel-before-launch discipline as the debounce path.
        remoteFetchTask?.cancel()

        let token = UUID()
        searchToken = token
        isLoadingRemote = true
        remoteResults = []
        remoteError = nil

        remoteFetchTask = Task {
            if Task.isCancelled { return }
            await performRemoteSearch(query: trimmed, token: token)
        }
    }

    /// Fires USDA and OFF concurrently. One failing source does NOT block the
    /// other — partial coverage is preferred over an error wall. OFF is only
    /// queried when `includeBranded` is on (OFF's catalog is overwhelmingly
    /// branded; querying it for `includeBranded=false` would clutter the
    /// generic-food experience).
    ///
    /// Each task returns a `(hits, errorString?)` tuple so we can surface
    /// the actual error message when a source fails AND we ended up with no
    /// results to display. Without this, silent USDA errors (missing API
    /// key, rate limit, network blip) would show as an empty list with no
    /// explanation — bug fixed in the v2.2.1 first-cut after Mike hit it.
    private func performRemoteSearch(query q: String, token: UUID) async {
        async let usdaTask: ([USDAService.SearchHit], String?) = {
            do {
                let hits = try await USDAService.search(q, includeBranded: includeBranded)
                return (hits, nil)
            } catch is CancellationError {
                // Cancelled by a new keystroke — suppress; the next fetch
                // will overwrite the view state anyway.
                return ([], nil)
            } catch let e as USDAService.USDAError {
                // Swallow HTTP 400 specifically: api.data.gov's fronting
                // nginx occasionally returns 400 Bad Request on rapid /
                // bursty requests even when our payload is valid. It's
                // transient, server-side, and not actionable on our end.
                // Show no results for USDA this round and let the user
                // refine the query. ALL OTHER USDA errors (missing key,
                // network failure, 401/403/429, decode error) still
                // surface so real problems remain visible.
                if case .http(400, _) = e {
                    return ([], nil)
                }
                return ([], e.localizedDescription)
            } catch {
                return ([], error.localizedDescription)
            }
        }()
        async let offTask: ([OpenFoodFactsService.SearchHit], String?) = {
            // OFF gated by branded toggle. Skipped is NOT failed.
            guard includeBranded else { return ([], nil) }
            do {
                let hits = try await OpenFoodFactsService.search(q)
                return (hits, nil)
            } catch is CancellationError {
                return ([], nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }()

        let (usdaResult, offResult) = await (usdaTask, offTask)
        let usdaHits = usdaResult.0
        let usdaErr  = usdaResult.1
        let offHits  = offResult.0
        let offErr   = offResult.1

        // If this whole search was cancelled (user typed another character),
        // bail without touching the view state — a fresh debounce is already
        // queued.
        if Task.isCancelled { return }

        let merged = mergeAndDedupe(usda: usdaHits, off: offHits, query: q)

        await MainActor.run {
            guard token == searchToken else { return }
            remoteResults = merged
            isLoadingRemote = false

            // Surface errors only when the merged list is empty. If we have
            // even partial coverage, suppress the error — a working list +
            // a red wall is more confusing than the list alone.
            if !merged.isEmpty {
                remoteError = nil
            } else if let e = usdaErr, let o = offErr {
                remoteError = "USDA: \(e)\nOpen Food Facts: \(o)"
            } else if let e = usdaErr {
                remoteError = e
            } else if let o = offErr {
                remoteError = o
            } else {
                remoteError = nil
            }
        }
    }

    // MARK: - Merge + dedupe (v2.2.1)

    /// Merges USDA + OFF results into one ranked list, dropping cross-source
    /// and OFF-vs-OFF duplicates. The dedupe heuristic is intentionally
    /// READABLE and TUNABLE — Mike will tweak when real-world results expose
    /// the edges:
    ///
    ///   1. Score each result by relevance to the query (exact match >
    ///      starts-with > word-boundary > contains > weak match).
    ///   2. Sort merged, USDA wins ties (so USDA appears first when scores
    ///      are equal).
    ///   3. Walk the sorted list keeping a runner. A new candidate is
    ///      considered a duplicate of an already-kept result when:
    ///        • normalized names match (or one contains the other for >5
    ///          chars), AND
    ///        • normalized brands match, AND
    ///        • caloriesPer100g are within ±15% of each other.
    ///   4. On collision, the already-kept (earlier in sort order) result
    ///      wins. Because USDA wins ties, USDA wins cross-source collisions.
    ///
    /// If the heuristic ever over-collapses (hides a real distinct food) or
    /// under-collapses (lets a true duplicate through), TUNE THE THRESHOLDS
    /// in `isLikelyDuplicate(_:_:)` — that's the knob.
    private func mergeAndDedupe(
        usda: [USDAService.SearchHit],
        off: [OpenFoodFactsService.SearchHit],
        query: String
    ) -> [MergedHit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Build candidates with relevance scores.
        struct Scored {
            let hit: MergedHit
            let score: Int
        }
        var scored: [Scored] = []
        for h in usda {
            let m = MergedHit(from: h)
            scored.append(Scored(hit: m, score: relevanceScore(name: m.name, brand: m.brand, query: q)))
        }
        for h in off {
            let m = MergedHit(from: h)
            scored.append(Scored(hit: m, score: relevanceScore(name: m.name, brand: m.brand, query: q)))
        }

        // Sort: higher score first; on ties, USDA before OFF (preference
        // baked into the source-tag enum's rawValue).
        let sorted = scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.hit.source != b.hit.source {
                return a.hit.source == .usda
            }
            return false
        }

        // Dedupe walk.
        var kept: [MergedHit] = []
        for candidate in sorted {
            let isDup = kept.contains { isLikelyDuplicate(candidate.hit, $0) }
            if !isDup {
                kept.append(candidate.hit)
            }
        }
        return kept
    }

    /// Relevance scorer. Tweak weights if the order feels wrong in practice.
    private func relevanceScore(name: String, brand: String?, query q: String) -> Int {
        guard !q.isEmpty else { return 0 }
        let nLower = name.lowercased()
        let bLower = (brand ?? "").lowercased()
        if nLower == q { return 1000 }
        if nLower.hasPrefix(q) { return 850 }
        // Word-boundary prefix (any whitespace-delimited word starts with q).
        if nLower.split(separator: " ").contains(where: { $0.hasPrefix(q) }) {
            return 700
        }
        if nLower.contains(q) { return 550 }
        if !bLower.isEmpty && bLower.contains(q) { return 400 }
        return 100
    }

    /// Heuristic duplicate check. See `mergeAndDedupe`'s doc-comment for the
    /// rule and where to tune.
    private func isLikelyDuplicate(_ a: MergedHit, _ b: MergedHit) -> Bool {
        let nameA = normalizeForCompare(a.name)
        let nameB = normalizeForCompare(b.name)
        let brandA = normalizeForCompare(a.brand ?? "")
        let brandB = normalizeForCompare(b.brand ?? "")

        // Name match: identical, OR one contains the other when the shorter
        // side is >5 chars (avoids "egg" matching "eggplant").
        let nameMatch: Bool = {
            if nameA == nameB { return true }
            let shorter = nameA.count <= nameB.count ? nameA : nameB
            let longer  = nameA.count <= nameB.count ? nameB : nameA
            return shorter.count > 5 && longer.contains(shorter)
        }()
        guard nameMatch else { return false }

        // Brand match: both empty (generic foods) OR identical.
        let brandMatch = brandA == brandB
        guard brandMatch else { return false }

        // Calorie match: within ±15% tolerance.
        let calA = a.caloriesPer100g
        let calB = b.caloriesPer100g
        guard calA > 0 || calB > 0 else { return true }   // both zero → call it a dup
        let tolerance = max(calA, calB) * 0.15
        return abs(calA - calB) <= tolerance
    }

    private func normalizeForCompare(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Picking a result

    private func pick(library food: LibraryFood) {
        Haptic.light()
        pendingPick = Pick(prefill: LibraryService.toPrefill(food))
    }

    private func pick(merged hit: MergedHit) {
        Haptic.light()
        pendingPick = Pick(prefill: hit.prefill)
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
        HealthSync.onFoodSaved(entry)

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
            HealthSync.onFoodDeleting(entry)
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

// MARK: - MergedHit + MergedRow (v2.2.1)

/// One-row-per-source-of-truth merger of USDA + OFF hits. Carries the
/// prefill needed to land in Confirm. Identity is composite ("usda:<id>" /
/// "off:<code>") so SwiftUI's ForEach can dedupe across re-renders cleanly.
struct MergedHit: Identifiable, Hashable {
    enum Source: String { case usda, off }

    let id: String
    let source: Source
    let name: String
    let brand: String?
    let caloriesPer100g: Double
    /// USDA's data type label (Foundation / SR Legacy / Survey / Branded);
    /// nil for OFF, which has no equivalent classification.
    let dataType: String?
    let prefill: ConfirmFoodView.Prefill

    init(from hit: USDAService.SearchHit) {
        self.id = "usda:\(hit.id)"
        self.source = .usda
        self.name = hit.name
        self.brand = hit.brand
        self.caloriesPer100g = hit.caloriesPer100g
        self.dataType = hit.dataType
        self.prefill = hit.toPrefill()
    }

    init(from hit: OpenFoodFactsService.SearchHit) {
        self.id = "off:\(hit.id)"
        self.source = .off
        self.name = hit.name
        self.brand = hit.brand
        self.caloriesPer100g = hit.caloriesPer100g
        self.dataType = nil
        self.prefill = hit.toPrefill()
    }

    static func == (lhs: MergedHit, rhs: MergedHit) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct MergedRow: View {
    let hit: MergedHit
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        // Source tag — small, unobtrusive, always present.
                        Text(sourceLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(sourceColor.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(sourceColor)
                        // USDA dataType pill stays so you can distinguish
                        // Foundation/SR/Survey vs Branded at a glance.
                        if let dataType = hit.dataType, !dataType.isEmpty {
                            Text(dataType)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(usdaTypeColor.opacity(0.15))
                                .clipShape(Capsule())
                                .foregroundStyle(usdaTypeColor)
                        }
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

    /// "USDA" / "OFF" — visible at a glance so lab-analyzed vs crowd-sourced
    /// data is never ambiguous.
    private var sourceLabel: String {
        switch hit.source {
        case .usda: return "USDA"
        case .off:  return "OFF"
        }
    }

    /// USDA = green (lab-quality). OFF = amber (crowd-sourced — handle with
    /// slightly more skepticism).
    private var sourceColor: Color {
        switch hit.source {
        case .usda: return .green
        case .off:  return .orange
        }
    }

    private var usdaTypeColor: Color {
        switch hit.dataType {
        case "Foundation":     return .green
        case "SR Legacy":      return .blue
        case "Survey (FNDDS)": return .purple
        case "Branded":        return .orange
        default:               return .gray
        }
    }
}
