import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context

    /// The calendar day currently being viewed. Hoisted to RootView so the Add
        /// tab can read the same date. All cards and queries filter to entries on
        /// this day.
        @Binding var selectedDate: Date

    /// Set by RootView when a notification deep-link wants Today to open a
    /// specific MealDetailSheet. We consume it in .onChange and clear it.
    @Binding var pendingMealKey: String?

    @State private var showingDatePicker = false

    @State private var customWaterAmount: String = ""
    @State private var showingWaterEntries = false
    @State private var showingTotalEdit = false
    @State private var totalEditText = ""
    @State private var showingBreakdown = false
    @State private var entryToEdit: FoodEntry?
    @State private var undoMessage: String?
    @State private var pendingDeleteIDs: [PersistentIdentifier] = []
    @State private var undoTask: Task<Void, Never>?
    @State private var openMeal: String?

    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goalsList: [UserGoals]
    @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allWater: [WaterEntry]

    // MARK: - Date-aware queries

    private var entriesForSelectedDay: [FoodEntry] {
        allEntries.filter {
            Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) &&
            $0.pendingDeleteAt == nil
        }
    }

    private var waterOzForSelectedDay: Double {
        allWater
            .filter {
                Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) &&
                $0.pendingDeleteAt == nil
            }
            .reduce(0) { $0 + $1.amountOz }
    }

    private var goals: UserGoals {
        if let g = goalsList.first { return g }
        let new = UserGoals()
        context.insert(new)
        return new
    }

    private var totals: (cal: Double, p: Double, c: Double, f: Double) {
        entriesForSelectedDay.reduce((0, 0, 0, 0)) { acc, e in
            (acc.0 + e.calories * e.servings,
             acc.1 + e.protein  * e.servings,
             acc.2 + e.carbs    * e.servings,
             acc.3 + e.fat      * e.servings)
        }
    }

    // MARK: - Date helpers

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    /// Returns a timestamp for newly-saved entries. If viewing today, uses .now
    /// to preserve real time-of-day. If viewing a past day, uses noon of that day —
    /// the entry only needs to land on the correct calendar day, hour doesn't matter
    /// for display (entries are grouped by mealType field, not by hour).
    private func timestampForSave() -> Date {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) {
            return .now
        }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }

    private func shiftDay(_ days: Int) {
        let cal = Calendar.current
        guard let newDate = cal.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let normalized = cal.startOfDay(for: newDate)
        // Never allow future dates.
        let todayStart = cal.startOfDay(for: .now)
        guard normalized <= todayStart else { return }
        Haptic.light()
        selectedDate = normalized
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        dailyTotalsCard
                        waterCard
                        ForEach(mealOrder, id: \.self) { meal in
                            mealSummaryCard(meal: meal)
                        }
                    }
                    .padding()
                }

                // Undo toast
                if let undoMessage {
                    HStack(spacing: 12) {
                        Text(undoMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Undo") { undoDelete() }
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
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        shiftDay(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        showingDatePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(dateLabel)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        shiftDay(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(isToday)
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                datePickerSheet
            }
            .sheet(item: $entryToEdit) { entry in
                EditEntrySheet(entry: entry)
            }
            .sheet(item: Binding(
                get: { openMeal.map(MealID.init) },
                set: { openMeal = $0?.value }
            )) { mealID in
                MealDetailSheet(
                    mealKey: mealID.value,
                    mealLabel: mealLabel(mealID.value),
                    selectedDate: selectedDate,
                    onEditEntry: { entry in entryToEdit = entry },
                    onSoftDelete: softDelete
                )
            }
            .onChange(of: pendingMealKey) { _, newValue in
                guard let meal = newValue else { return }
                openMeal = meal
                pendingMealKey = nil
            }
            .onAppear {
                // Handle the launch-from-notification case: RootView may have
                // set pendingMealKey before TodayView mounted.
                if let meal = pendingMealKey {
                    openMeal = meal
                    pendingMealKey = nil
                }
            }
        }
    }

    // MARK: - Date picker sheet

    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Pick a day",
                    selection: $selectedDate,
                    in: ...Calendar.current.startOfDay(for: .now),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                Spacer()
            }
            .navigationTitle("Pick a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today") {
                        selectedDate = Calendar.current.startOfDay(for: .now)
                        showingDatePicker = false
                    }
                    .disabled(isToday)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingDatePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Daily totals card

    private var dailyTotalsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(
                    label: "Cal",
                    value: "\(Int(totals.cal))",
                    sub: "/ \(Int(goals.calorieGoal))",
                    progress: totals.cal / max(goals.calorieGoal, 1),
                    color: .orange
                )
                StatTile(
                    label: "Protein",
                    value: "\(Int(totals.p))g",
                    sub: "/ \(Int(goals.proteinGoal))g",
                    progress: totals.p / max(goals.proteinGoal, 1),
                    color: .red
                )
                StatTile(
                    label: "Carbs",
                    value: "\(Int(totals.c))g",
                    sub: "/ \(Int(goals.carbsGoal))g",
                    progress: totals.c / max(goals.carbsGoal, 1),
                    color: .blue
                )
                StatTile(
                    label: "Fat",
                    value: "\(Int(totals.f))g",
                    sub: "/ \(Int(goals.fatGoal))g",
                    progress: totals.f / max(goals.fatGoal, 1),
                    color: .yellow
                )
            }

            Button {
                showingBreakdown = true
            } label: {
                HStack(spacing: 4) {
                    Text("Full breakdown")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingBreakdown) {
                    NutritionBreakdownSheet(selectedDate: selectedDate)
                }
    }

    // MARK: - Water

    private var waterCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.cyan)
                Text("Water")
                    .font(.headline)
                Spacer()
                Button {
                    totalEditText = "\(Int(waterOzForSelectedDay))"
                    showingTotalEdit = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(Int(waterOzForSelectedDay)) / \(Int(goals.waterGoalOz)) oz")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    LongPressGesture().onEnded { _ in
                        showingWaterEntries = true
                    }
                )
            }

            ProgressView(value: min(waterOzForSelectedDay / max(goals.waterGoalOz, 1), 1))
                .tint(.cyan)

            HStack(spacing: 8) {
                TextField("Custom oz", text: $customWaterAmount)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))

                Button {
                    if let amount = Double(customWaterAmount), amount != 0 {
                        logWater(amount)
                        customWaterAmount = ""
                        dismissKeyboard()
                    }
                } label: {
                    Text("Log")
                        .font(.callout.weight(.semibold))
                        .frame(width: 64)
                        .padding(.vertical, 10)
                        .background(.cyan, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(Double(customWaterAmount) == nil || customWaterAmount.isEmpty)
                .opacity((Double(customWaterAmount) ?? 0) == 0 ? 0.4 : 1)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showingWaterEntries) {
            WaterEntriesSheet(selectedDate: selectedDate)
        }
        .alert("Set water total", isPresented: $showingTotalEdit) {
            TextField("oz", text: $totalEditText)
                .keyboardType(.numbersAndPunctuation)
            Button("Cancel", role: .cancel) {}
            Button("Set") { applyTotalEdit() }
        } message: {
            Text("\(dateLabel): \(Int(waterOzForSelectedDay)) oz. Type the new total in oz.")
        }
    }

    // MARK: - Meal summary card

    private func mealSummaryCard(meal: String) -> some View {
        let entries = entriesForMeal(meal)
        let cal = mealCalories(meal)
        let isEmpty = entries.isEmpty

        return Button {
            openMeal = meal
        } label: {
            HStack {
                Text(mealLabel(meal))
                    .font(.headline)
                    .foregroundStyle(isEmpty ? .secondary : .primary)
                Spacer()
                if isEmpty {
                    Text("—")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(Int(cal)) cal")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                Color(.secondarySystemGroupedBackground)
                    .opacity(isEmpty ? 0.6 : 1.0),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var mealOrder: [String] { ["breakfast", "lunch", "dinner", "snack"] }

    private func entriesForMeal(_ meal: String) -> [FoodEntry] {
        entriesForSelectedDay.filter { $0.mealType == meal }
    }

    private func mealCalories(_ meal: String) -> Double {
        entriesForMeal(meal).reduce(0) { $0 + $1.calories * $1.servings }
    }

    private func mealLabel(_ meal: String) -> String {
        switch meal {
        case "breakfast": return "Breakfast"
        case "lunch":     return "Lunch"
        case "dinner":    return "Dinner"
        case "snack":     return "Snacks"
        default:          return meal.capitalized
        }
    }

    private func logWater(_ amountOz: Double) {
        guard amountOz != 0 else { return }
        Haptic.light()
        let entry = WaterEntry(amountOz: amountOz, loggedAt: timestampForSave())
        context.insert(entry)
        HealthSync.onWaterSaved(entry)
    }

    private func softDelete(_ entry: FoodEntry) {
        Haptic.medium()
        entry.pendingDeleteAt = .now
        pendingDeleteIDs.append(entry.persistentModelID)
        undoMessage = "Deleted \(entry.name)"

        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run { commitPendingDeletes() }
        }
    }

    private func undoDelete() {
        Haptic.light()
        undoTask?.cancel()
        for id in pendingDeleteIDs {
            if let entry = allEntries.first(where: { $0.persistentModelID == id }) {
                entry.pendingDeleteAt = nil
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func commitPendingDeletes() {
        for id in pendingDeleteIDs {
            if let entry = allEntries.first(where: { $0.persistentModelID == id }) {
                HealthSync.onFoodDeleting(entry)
                context.delete(entry)
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func applyTotalEdit() {
        guard let newTotal = Double(totalEditText.trimmingCharacters(in: .whitespaces)) else { return }
        let diff = newTotal - waterOzForSelectedDay
        if diff != 0 {
            Haptic.light()
            let entry = WaterEntry(amountOz: diff, loggedAt: timestampForSave())
            context.insert(entry)
            HealthSync.onWaterSaved(entry)
        }
        dismissKeyboard()
    }

    // Identifiable wrapper so sheet(item:) can use a String
    private struct MealID: Identifiable {
        let value: String
        var id: String { value }
    }

    // MARK: - Subviews

    private struct StatTile: View {
        let label: String
        let value: String
        let sub: String
        let progress: Double
        let color: Color

        var body: some View {
            VStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ProgressView(value: min(progress, 1))
                    .tint(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - EntryRow

    struct EntryRow: View {
        let entry: FoodEntry

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: iconForSource)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.body)
                    Text("\(formatted(entry.servings)) \(entry.servingUnit)" +
                         (entry.brand.map { " • \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(entry.calories * entry.servings)) cal")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }

        private var iconForSource: String {
            switch entry.source {
            case "barcode": return "barcode.viewfinder"
            case "photo":   return "camera.fill"
            case "search":  return "magnifyingglass"
            default:        return "square.and.pencil"
            }
        }

        private func formatted(_ d: Double) -> String {
            FoodFormat.value(d)
        }
    }

    // MARK: - WaterEntriesSheet

    struct WaterEntriesSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var context
        let selectedDate: Date
        @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allWater: [WaterEntry]

        @State private var undoMessage: String?
        @State private var pendingDeleteIDs: [PersistentIdentifier] = []
        @State private var undoTask: Task<Void, Never>?

        private var entriesForDay: [WaterEntry] {
            allWater.filter {
                Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) &&
                $0.pendingDeleteAt == nil
            }
        }

        private var total: Double {
            entriesForDay.reduce(0) { $0 + $1.amountOz }
        }

        private var sheetTitle: String {
            let cal = Calendar.current
            if cal.isDateInToday(selectedDate) { return "Today's water" }
            if cal.isDateInYesterday(selectedDate) { return "Yesterday's water" }
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "\(f.string(from: selectedDate)) — water"
        }

        private var totalLabel: String {
            let cal = Calendar.current
            if cal.isDateInToday(selectedDate) { return "Total today" }
            if cal.isDateInYesterday(selectedDate) { return "Total yesterday" }
            return "Total"
        }

        var body: some View {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    List {
                        Section {
                            HStack {
                                Text(totalLabel)
                                    .font(.headline)
                                Spacer()
                                Text("\(formatted(total)) oz")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(.cyan)
                            }
                        }

                        Section("Entries") {
                            if entriesForDay.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "drop")
                                        .foregroundStyle(.cyan.opacity(0.6))
                                    Text("Nothing logged.")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                ForEach(entriesForDay) { entry in
                                    HStack {
                                        Image(systemName: entry.amountOz < 0 ? "minus.circle.fill" : "drop.fill")
                                            .foregroundStyle(entry.amountOz < 0 ? .red : .cyan)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(formatted(entry.amountOz)) oz")
                                                .font(.body.monospacedDigit())
                                            Text(entry.loggedAt, style: .time)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            softDelete(entry)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let undoMessage {
                        HStack(spacing: 12) {
                            Text(undoMessage)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Spacer()
                            Button("Undo") { undoDelete() }
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
                .navigationTitle(sheetTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onDisappear { commitPendingDeletes() }
            }
        }

        private func softDelete(_ entry: WaterEntry) {
            Haptic.medium()
            entry.pendingDeleteAt = .now
            pendingDeleteIDs.append(entry.persistentModelID)
            undoMessage = "Deleted \(formatted(entry.amountOz)) oz"

            undoTask?.cancel()
            undoTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { commitPendingDeletes() }
            }
        }

        private func undoDelete() {
            Haptic.light()
            undoTask?.cancel()
            for id in pendingDeleteIDs {
                if let entry = allWater.first(where: { $0.persistentModelID == id }) {
                    entry.pendingDeleteAt = nil
                }
            }
            pendingDeleteIDs.removeAll()
            undoMessage = nil
        }

        private func commitPendingDeletes() {
            undoTask?.cancel()
            for id in pendingDeleteIDs {
                if let entry = allWater.first(where: { $0.persistentModelID == id }) {
                    HealthSync.onWaterDeleting(entry)
                    context.delete(entry)
                }
            }
            pendingDeleteIDs.removeAll()
            undoMessage = nil
        }

        private func formatted(_ d: Double) -> String {
            let sign = d < 0 ? "−" : ""
            return "\(sign)\(FoodFormat.value(Swift.abs(d)))"
        }
    }
}

// MARK: - MealDetailSheet
struct MealDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]

    let mealKey: String
    let mealLabel: String
    let selectedDate: Date
    let onEditEntry: (FoodEntry) -> Void
    let onSoftDelete: (FoodEntry) -> Void

    @State private var showingManual = false
    @State private var showingSearch = false
    @State private var showingScanner = false
    @State private var showingPhoto = false

    private var entries: [FoodEntry] {
        allEntries.filter {
            Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) &&
            $0.pendingDeleteAt == nil &&
            $0.mealType == mealKey
        }
    }

    private var totals: (cal: Double, p: Double, c: Double, f: Double) {
        entries.reduce((0, 0, 0, 0)) { acc, e in
            (acc.0 + e.calories * e.servings,
             acc.1 + e.protein  * e.servings,
             acc.2 + e.carbs    * e.servings,
             acc.3 + e.fat      * e.servings)
        }
    }

    /// Date to attach to new entries logged from this sheet. If viewing today,
    /// use .now (real time-of-day); if past, use noon of selectedDate.
    private var saveDate: Date {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) {
            return .now
        }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(totals.cal)) cal")
                                .font(.title2.monospacedDigit().weight(.semibold))
                            Text("P \(Int(totals.p))g · C \(Int(totals.c))g · F \(Int(totals.f))g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                Section("Entries") {
                    if entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("Nothing logged for \(mealLabel.lowercased()) yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(entries) { entry in
                            Button {
                                onEditEntry(entry)
                            } label: {
                                TodayView.EntryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onSoftDelete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Add to \(mealLabel.lowercased())") {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search foods", systemImage: "magnifyingglass")
                            .foregroundStyle(.green)
                    }
                    Button {
                        showingScanner = true
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                            .foregroundStyle(.orange)
                    }
                    Button {
                        showingPhoto = true
                    } label: {
                        Label("Photo estimate", systemImage: "camera.fill")
                            .foregroundStyle(.pink)
                    }
                    Button {
                        showingManual = true
                    } label: {
                        Label("Manual entry", systemImage: "square.and.pencil")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .navigationTitle(mealLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingManual) {
                ManualEntrySheet(defaultMeal: mealKey, defaultDate: saveDate)
            }
            .sheet(isPresented: $showingSearch) {
                SearchSheet(defaultMeal: mealKey, defaultDate: saveDate)
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerSheet(defaultMeal: mealKey, defaultDate: saveDate)
            }
            .sheet(isPresented: $showingPhoto) {
                PhotoLogSheet(defaultMeal: mealKey, defaultDate: saveDate)
            }
        }
    }
}
