import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @State private var customWaterAmount: String = ""
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]
    @Query private var goalsList: [UserGoals]

    private var todayEntries: [FoodEntry] {
        allEntries.filter { Calendar.current.isDateInToday($0.loggedAt) }
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
            ScrollView {
                VStack(spacing: 24) {
                    summaryCard
                    macroBreakdown
                    waterCard
                    entriesSection
                }
                .padding()
            }
            .navigationTitle("Today")
            .background(Color(.systemGroupedBackground))
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            Text("\(Int(totals.cal))")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("of \(Int(goals.calorieGoal)) kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: min(totals.cal / max(goals.calorieGoal, 1), 1))
                .tint(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
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
                    Text("\(Int(todayWaterOz)) / \(Int(goals.waterGoalOz)) oz")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(todayWaterOz / max(goals.waterGoalOz, 1), 1))
                    .tint(.cyan)

                HStack(spacing: 8) {
                    waterButton(amount: -8, label: "−8", tint: .red)
                    waterButton(amount: 8,  label: "+8",  tint: .cyan)
                    waterButton(amount: 12, label: "+12", tint: .cyan)
                    waterButton(amount: 16, label: "+16", tint: .cyan)
                }

                HStack(spacing: 8) {
                    TextField("Custom oz", text: $customWaterAmount)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10))

                    Button {
                        if let amount = Double(customWaterAmount), amount != 0 {
                            logWater(amount)
                            customWaterAmount = ""
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
        }

        private func waterButton(amount: Double, label: String, tint: Color) -> some View {
            Button {
                logWater(amount)
            } label: {
                Text(label)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
        }

        private func logWater(_ amountOz: Double) {
            // For negatives, we just delete the most recent entry instead of inserting negative.
            if amountOz < 0 {
                let todays = allWater.filter { Calendar.current.isDateInToday($0.loggedAt) }
                if let mostRecent = todays.first {
                    context.delete(mostRecent)
                }
            } else {
                context.insert(WaterEntry(amountOz: amountOz))
            }
        }
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logged today")
                .font(.headline)
                .padding(.horizontal, 4)

            if todayEntries.isEmpty {
                Text("Nothing yet. Tap Add to log your first item.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(todayEntries) { entry in
                    EntryRow(entry: entry)
                        .swipeActions {
                            Button(role: .destructive) {
                                context.delete(entry)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
    }
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
            Text("\(Int(entry.calories * entry.servings)) kcal")
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
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(d))
            : String(format: "%.1f", d)
    }
}
