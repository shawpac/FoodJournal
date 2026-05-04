import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @State private var customWaterAmount: String = ""
    @State private var showingWaterEntries = false
    @State private var showingTotalEdit = false
    @State private var totalEditText = ""
    @State private var showingBreakdown = false
    @State private var entryToEdit: FoodEntry?
    @State private var undoMessage: String?
    @State private var pendingDeleteIDs: [PersistentIdentifier] = []
    @State private var undoTask: Task<Void, Never>?
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goalsList: [UserGoals]

    private var todayEntries: [FoodEntry] {
        allEntries.filter { Calendar.current.isDateInToday($0.loggedAt) && $0.pendingDeleteAt == nil }
    }

    private var goals: UserGoals {
        if let g = goalsList.first { return g }
        let new = UserGoals()
        context.insert(new)
        return new
    }

    @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allWater: [WaterEntry]
    private var todayWaterOz: Double {
        allWater
            .filter { Calendar.current.isDateInToday($0.loggedAt) }
            .reduce(0) { $0 + $1.amountOz }
    }

    private var totals: (cal: Double, p: Double, c: Double, f: Double) {
        todayEntries.reduce((0, 0, 0, 0)) { acc, e in
            (acc.0 + e.calories * e.servings,
             acc.1 + e.protein  * e.servings,
             acc.2 + e.carbs    * e.servings,
             acc.3 + e.fat      * e.servings)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 24) {
                        summaryCard
                        macroBreakdown
                        waterCard
                        entriesSection
                    }
                    .padding()
                }

                // Undo toast — overlays the bottom of the view, above the tab bar.
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
            .navigationTitle("Today")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            Text("\(Int(totals.cal))")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("of \(Int(goals.calorieGoal)) Calories")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: min(totals.cal / max(goals.calorieGoal, 1), 1))
                .tint(.orange)

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
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $showingBreakdown) {
            NutritionBreakdownSheet()
        }
    }

    private var macroBreakdown: some View {
        HStack(spacing: 12) {
            MacroPill(label: "Protein", value: totals.p, goal: goals.proteinGoal, color: .red)
            MacroPill(label: "Carbs",   value: totals.c, goal: goals.carbsGoal,   color: .blue)
            MacroPill(label: "Fat",     value: totals.f, goal: goals.fatGoal,     color: .yellow)
        }
    }

    private var waterCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "drop.fill")
                    .foregroundStyle(.cyan)
                Text("Water")
                    .font(.headline)
                Spacer()
                Button {
                    totalEditText = "\(Int(todayWaterOz))"
                    showingTotalEdit = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(Int(todayWaterOz)) / \(Int(goals.waterGoalOz)) oz")
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

            ProgressView(value: min(todayWaterOz / max(goals.waterGoalOz, 1), 1))
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
            WaterEntriesSheet()
        }
        .alert("Set water total", isPresented: $showingTotalEdit) {
            TextField("oz", text: $totalEditText)
                .keyboardType(.numbersAndPunctuation)
            Button("Cancel", role: .cancel) {}
            Button("Set") { applyTotalEdit() }
        } message: {
            Text("Today: \(Int(todayWaterOz)) oz. Type the new total in oz.")
        }
    }

    private func logWater(_ amountOz: Double) {
        guard amountOz != 0 else { return }
        Haptic.light()
        context.insert(WaterEntry(amountOz: amountOz))
    }

    /// Soft-delete a food entry: mark it pending and schedule the actual delete.
    private func softDelete(_ entry: FoodEntry) {
        Haptic.medium()
        entry.pendingDeleteAt = .now
        pendingDeleteIDs.append(entry.persistentModelID)
        undoMessage = "Deleted \(entry.name)"

        // Cancel any prior undo timer and start fresh — gives the user 5s from
        // their MOST RECENT delete, not 5s from the first one in a chain.
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run { commitPendingDeletes() }
        }
    }

    /// User tapped Undo — restore everything currently pending.
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

    /// Timer expired — actually delete everything that's still pending.
    private func commitPendingDeletes() {
        for id in pendingDeleteIDs {
            if let entry = allEntries.first(where: { $0.persistentModelID == id }) {
                context.delete(entry)
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func applyTotalEdit() {
        guard let newTotal = Double(totalEditText.trimmingCharacters(in: .whitespaces)) else { return }
        let diff = newTotal - todayWaterOz
        if diff != 0 {
            Haptic.light()
            context.insert(WaterEntry(amountOz: diff))
        }
        dismissKeyboard()
    }

    // Order in which meal sections appear, regardless of when they were logged.
    private var mealOrder: [String] { ["breakfast", "lunch", "dinner", "snack"] }

    private func entriesForMeal(_ meal: String) -> [FoodEntry] {
        todayEntries.filter { $0.mealType == meal }
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

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if todayEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange.opacity(0.7))
                    Text("Ready when you are")
                        .font(.headline)
                    Text("Tap **Add** below to log your first item of the day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(mealOrder, id: \.self) { meal in
                    let entries = entriesForMeal(meal)
                    if !entries.isEmpty {
                        mealCard(meal: meal, entries: entries)
                    }
                }
            }
        }
        .sheet(item: $entryToEdit) { entry in
            EditEntrySheet(entry: entry)
        }
    }

    private func mealCard(meal: String, entries: [FoodEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(mealLabel(meal))
                    .font(.headline)
                Spacer()
                Text("\(Int(mealCalories(meal))) cal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            List {
                ForEach(entries) { entry in
                    Button {
                        entryToEdit = entry
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color(.tertiarySystemGroupedBackground))
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            softDelete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(entries.count) * 76)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private struct MacroPill: View {
        let label: String
        let value: Double
        let goal: Double
        let color: Color

        var body: some View {
            VStack(spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("\(Int(value))g")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                Text("/ \(Int(goal))g")
                    .font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: min(value / max(goal, 1), 1)).tint(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private struct EntryRow: View {
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

    struct WaterEntriesSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var context
        @Query(sort: \WaterEntry.loggedAt, order: .reverse) private var allWater: [WaterEntry]

        private var todayEntries: [WaterEntry] {
            allWater.filter { Calendar.current.isDateInToday($0.loggedAt) }
        }

        private var total: Double {
            todayEntries.reduce(0) { $0 + $1.amountOz }
        }

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        HStack {
                            Text("Total today")
                                .font(.headline)
                            Spacer()
                            Text("\(formatted(total)) oz")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.cyan)
                        }
                    }

                    Section("Entries") {
                        if todayEntries.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "drop")
                                    .foregroundStyle(.cyan.opacity(0.6))
                                Text("Nothing logged yet — pour one in.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(todayEntries) { entry in
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
                            }
                            .onDelete(perform: delete)
                        }
                    }
                }
                .navigationTitle("Today's water")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        private func delete(at offsets: IndexSet) {
            Haptic.medium()
            for index in offsets {
                context.delete(todayEntries[index])
            }
        }

        private func formatted(_ d: Double) -> String {
            let sign = d < 0 ? "−" : ""
            return "\(sign)\(FoodFormat.value(Swift.abs(d)))"
        }
    }
}

