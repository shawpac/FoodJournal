import SwiftUI
import SwiftData

/// v2.1a — Manages today's individual ExerciseRepEntry bursts for one kind
/// (pushups or situps). Mirrors WaterEntriesSheet's UX: list, swipe-delete
/// with 5-second undo toast, commit on dismiss. Long-press the rep counter
/// on the Workouts tab to open this sheet.
struct DailyRepsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// "pushups" or "situps". Matches ExerciseRepEntry.kind.
    let kind: String

    @Query(sort: \ExerciseRepEntry.loggedAt, order: .reverse)
    private var allEntries: [ExerciseRepEntry]

    @State private var undoMessage: String?
    @State private var pendingDeleteIDs: [PersistentIdentifier] = []
    @State private var undoTask: Task<Void, Never>?

    private var entriesToday: [ExerciseRepEntry] {
        allEntries.filter {
            Calendar.current.isDateInToday($0.loggedAt) &&
            $0.kind == kind &&
            $0.pendingDeleteAt == nil
        }
    }

    private var total: Int {
        entriesToday.reduce(0) { $0 + $1.count }
    }

    private var sheetTitle: String {
        "Today's \(kind)"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section {
                        HStack {
                            Text("Total today")
                                .font(.headline)
                            Spacer()
                            Text("\(total)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("Bursts") {
                        if entriesToday.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.strengthtraining.functional")
                                    .foregroundStyle(.orange.opacity(0.6))
                                Text("Nothing logged.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(entriesToday) { entry in
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(entry.count)")
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

    private func softDelete(_ entry: ExerciseRepEntry) {
        Haptic.medium()
        entry.pendingDeleteAt = .now
        pendingDeleteIDs.append(entry.persistentModelID)
        undoMessage = "Deleted \(entry.count) \(kind)"

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
        undoTask?.cancel()
        for id in pendingDeleteIDs {
            if let entry = allEntries.first(where: { $0.persistentModelID == id }) {
                context.delete(entry)
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }
}
