import SwiftUI
import SwiftData

struct AddFoodView: View {
    @Environment(\.modelContext) private var context
    @Query private var library: [LibraryFood]

    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingManual = false
    @State private var showingSearch = false
    @State private var showingMostUsed = false

    /// Top 10 most used foods, hybrid-scored (useCount + recency).
    /// Single source of truth: pulls straight from LibraryFood.
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
            ScrollView {
                VStack(spacing: 16) {
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
            .navigationTitle("Add food")
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showingMostUsed)   { MostUsedSheet() }
            .sheet(isPresented: $showingSearch)     { SearchSheet() }
            .sheet(isPresented: $showingScanner)    { BarcodeScannerSheet() }
            .sheet(isPresented: $showingPhotoPicker) { PhotoLogSheet() }
            .sheet(isPresented: $showingManual)     { ManualEntrySheet() }
        }
    }
}

// MARK: - MostUsedSheet
/// Lists the top 10 most-used library foods. Tapping a row → ConfirmFoodView
/// (same flow as picking from Search). Swipe-left to remove from library.
struct MostUsedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var library: [LibraryFood]

    private struct Pick: Identifiable {
        let id = UUID()
        let prefill: ConfirmFoodView.Prefill
    }
    @State private var pendingPick: Pick?

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
                                pick(food)
                            } label: {
                                MostUsedRow(food: food)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(food)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Sorted by how often and how recently you log them. Swipe a row to remove from your library.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Most Used")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $pendingPick) { pick in
                NavigationStack {
                    ConfirmFoodView(prefill: pick.prefill, source: "search") {
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

    private func pick(_ food: LibraryFood) {
        Haptic.light()
        pendingPick = Pick(prefill: LibraryService.toPrefill(food))
    }

    private func remove(_ food: LibraryFood) {
        Haptic.medium()
        context.delete(food)
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
