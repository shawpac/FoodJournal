import SwiftUI
import PhotosUI
import SwiftData

struct AddFoodView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.loggedAt, order: .reverse) private var allEntries: [FoodEntry]

    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var showingManual = false
    @State private var relogTemplate: FoodEntry?

    // 10 most recent unique foods, deduped by name+brand
    private var recents: [FoodEntry] {
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for entry in allEntries {
            let key = "\(entry.name.lowercased())|\(entry.brand?.lowercased() ?? "")"
            if seen.insert(key).inserted {
                result.append(entry)
                if result.count >= 10 { break }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !recents.isEmpty {
                        recentsCard
                    }

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
            .sheet(isPresented: $showingScanner)    { BarcodeScannerSheet() }
            .sheet(isPresented: $showingPhotoPicker) { PhotoLogSheet() }
            .sheet(isPresented: $showingManual)     { ManualEntrySheet() }
            .sheet(item: $relogTemplate) { template in
                RelogSheet(template: template)
            }
        }
    }

    private var recentsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.purple)
                Text("Recents")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(recents) { entry in
                Button {
                    relogTemplate = entry
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let brand = entry.brand, !brand.isEmpty {
                                    Text(brand)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(formatted(entry.servings)) \(entry.servingUnit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(entry.calories * entry.servings)) kcal")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func formatted(_ d: Double) -> String {
        d.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(d))
            : String(format: "%.1f", d)
    }
}

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
