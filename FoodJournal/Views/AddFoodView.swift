import SwiftUI
import SwiftData

struct AddFoodView: View {
    @Environment(\.modelContext) private var context
    @Query private var library: [LibraryFood]

    /// Shared with TodayView via RootView. Drives the navigation title, the
    /// banner shown when on a past day, and the defaultDate threaded into all
    /// add flows.
    @Binding var selectedDate: Date

    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingManual = false
    @State private var showingSearch = false
    @State private var showingMostUsed = false

    /// Top 10 most used foods, hybrid-scored (useCount + recency).
    private var mostUsed: [LibraryFood] {
        let now = Date.now
        return library
            .sorted { score($0, now: now) > score($1, now: now) }
            .prefix(10)
            .map { $0 }
    }

    private func score(_ food: LibraryFood, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(food.lastUsedAt) / 86_400)
        let recency = 1.0 / (1.0 + ageDays)
        let frequency = Double(food.useCount)
        return frequency + recency * 5
    }

    // MARK: - Date awareness

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// The defaultDate to pass into add flows. nil when on today (so the entry
    /// init uses .now at save time, preserving real time-of-day). Otherwise
    /// noon-of-selectedDate to land cleanly on the right calendar day.
    private var defaultDateForSheets: Date? {
        if isToday { return nil }
        let cal = Calendar.current
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDate) ?? selectedDate
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: selectedDate)
    }

    private var navTitle: String {
        isToday ? "Add food" : "Add to \(dateLabel)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !isToday {
                        pastDayBanner
                    }

                    if !mostUsed.isEmpty {
                        AddOptionCard(
                            title: "Most Used",
                            subtitle: "Your \(mostUsed.count) most-logged food\(mostUsed.count == 1 ? "" : "s")",
                            systemImage: "star.fill",
                            tint: .purple
                        ) { showingMostUsed = true }
                    }

                    AddOptionCard(
                        title: "Search foods",
                        subtitle: "Your library + USDA database",
                        systemImage: "magnifyingglass",
                        tint: .green
                    ) { showingSearch = true }

                    AddOptionCard(
                        title: "Scan barcode",
                        subtitle: "Look up packaged food by UPC",
                        systemImage: "barcode.viewfinder",
                        tint: .orange
                    ) { showingScanner = true }

                    AddOptionCard(
                        title: "Photo estimate",
                        subtitle: "Use Claude to estimate nutrition from a photo",
                        systemImage: "camera.fill",
                        tint: .pink
                    ) { showingPhotoPicker = true }

                    AddOptionCard(
                        title: "Manual entry",
                        subtitle: "Type in name and macros",
                        systemImage: "square.and.pencil",
                        tint: .blue
                    ) { showingManual = true }
                }
                .padding()
            }
            .navigationTitle(navTitle)
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingMostUsed) {
                MostUsedSheet(defaultDate: defaultDateForSheets)
            }
            .sheet(isPresented: $showingSearch) {
                SearchSheet(defaultDate: defaultDateForSheets)
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerSheet(defaultDate: defaultDateForSheets)
            }
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoLogSheet(defaultDate: defaultDateForSheets)
            }
            .sheet(isPresented: $showingManual) {
                ManualEntrySheet(defaultDate: defaultDateForSheets)
            }
        }
    }

    // MARK: - Past-day banner

    private var pastDayBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Adding to \(dateLabel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("New entries go to this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Today") {
                Haptic.light()
                selectedDate = Calendar.current.startOfDay(for: .now)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
        }
        .padding(14)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - MostUsedSheet
/// Lists the top 10 most-used library foods. Tapping a row → ConfirmFoodView
/// (same flow as picking from Search). Swipe-left to remove from library
/// with 5-second undo via transient state (no schema change needed).
struct MostUsedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var library: [LibraryFood]

    /// Threaded through to ConfirmFoodView so picks from Most Used on a past
    /// day land on the right calendar date. nil = today (default behavior).
    let defaultDate: Date?

    init(defaultDate: Date? = nil) {
        self.defaultDate = defaultDate
    }

    private struct Pick: Identifiable {
        let id = UUID()
        let prefill: ConfirmFoodView.Prefill
    }
    @State private var pendingPick: Pick?

    @State private var pendingDeleteIDs: Set<PersistentIdentifier> = []
    @State private var undoMessage: String?
    @State private var undoTask: Task<Void, Never>?

    private var mostUsed: [LibraryFood] {
        let now = Date.now
        return library
            .sorted { score($0, now: now) > score($1, now: now) }
            .prefix(10)
            .map { $0 }
    }

    private func score(_ food: LibraryFood, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(food.lastUsedAt) / 86_400)
        let recency = 1.0 / (1.0 + ageDays)
        let frequency = Double(food.useCount)
        return frequency + recency * 5
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    if mostUsed.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "star")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text("No foods yet")
                                    .font(.headline)
                                Text("Log a few foods and they'll show up here.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section {
                            ForEach(mostUsed) { food in
                                Button {
                                    guard !pendingDeleteIDs.contains(food.persistentModelID) else { return }
                                    pick(food)
                                } label: {
                                    MostUsedRow(food: food)
                                        .opacity(pendingDeleteIDs.contains(food.persistentModelID) ? 0.35 : 1.0)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    if !pendingDeleteIDs.contains(food.persistentModelID) {
                                        Button(role: .destructive) {
                                            softRemove(food)
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } footer: {
                            Text("Sorted by how often and how recently you log them. Swipe a row to remove from your library — undo for 5 seconds.")
                                .font(.caption)
                        }
                    }
                }

                if let undoMessage {
                    HStack(spacing: 12) {
                        Text(undoMessage)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Undo") { undoRemove() }
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
            .navigationTitle("Most Used")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitPendingDeletes()
                        dismiss()
                    }
                }
            }
            .sheet(item: $pendingPick) { pick in
                NavigationStack {
                    ConfirmFoodView(prefill: pick.prefill, source: "search", defaultDate: defaultDate) {
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
            .onDisappear {
                commitPendingDeletes()
            }
        }
    }

    private func pick(_ food: LibraryFood) {
        Haptic.light()
        pendingPick = Pick(prefill: LibraryService.toPrefill(food))
    }

    private func softRemove(_ food: LibraryFood) {
        Haptic.medium()
        pendingDeleteIDs.insert(food.persistentModelID)
        undoMessage = "Removed \(food.name)"

        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run { commitPendingDeletes() }
        }
    }

    private func undoRemove() {
        Haptic.light()
        undoTask?.cancel()
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func commitPendingDeletes() {
        for id in pendingDeleteIDs {
            if let food = library.first(where: { $0.persistentModelID == id }) {
                context.delete(food)
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
        undoTask?.cancel()
    }
}

// MARK: - MostUsedRow
private struct MostUsedRow: View {
    let food: LibraryFood

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(.body)
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
}

// MARK: - AddOptionCard
private struct AddOptionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
