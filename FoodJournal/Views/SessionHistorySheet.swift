import SwiftUI
import SwiftData

/// v2.1a — Read-only history of past strength sessions. Designed to prove
/// the nested cascade (Session → Exercise → Set) persists correctly, NOT
/// for trend analysis. Trends / progression charts land in v2.1b.
struct SessionHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \StrengthSession.loggedAt, order: .reverse)
    private var allSessions: [StrengthSession]

    @State private var undoMessage: String?
    @State private var pendingDeleteIDs: [PersistentIdentifier] = []
    @State private var undoTask: Task<Void, Never>?

    private var sessions: [StrengthSession] {
        allSessions.filter { $0.pendingDeleteAt == nil }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    if sessions.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text("No sessions logged yet")
                                    .font(.headline)
                                Text("Log a strength session to see it here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section {
                            ForEach(sessions) { session in
                                NavigationLink {
                                    SessionDetailView(session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        softDelete(session)
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
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { commitPendingDeletes() }
        }
    }

    private func softDelete(_ session: StrengthSession) {
        Haptic.medium()
        session.pendingDeleteAt = .now
        pendingDeleteIDs.append(session.persistentModelID)
        let label = session.routineName ?? "Session"
        undoMessage = "Deleted \(label)"

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
            if let s = allSessions.first(where: { $0.persistentModelID == id }) {
                s.pendingDeleteAt = nil
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }

    private func commitPendingDeletes() {
        undoTask?.cancel()
        for id in pendingDeleteIDs {
            if let s = allSessions.first(where: { $0.persistentModelID == id }) {
                // Cascade rules on StrengthSession → LoggedExercise → LoggedSet
                // fire here, so the whole subtree is removed in one delete.
                context.delete(s)
            }
        }
        pendingDeleteIDs.removeAll()
        undoMessage = nil
    }
}

// MARK: - Row + detail

private struct SessionRow: View {
    let session: StrengthSession

    private var totalSets: Int {
        session.exercises.reduce(0) { $0 + $1.sets.count }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.routineName ?? "Blank session")
                    .font(.body)
                Text(session.loggedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.exercises.count) ex · \(totalSets) sets")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let mins = session.durationMinutes {
                    Text(formatDuration(mins))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

private struct SessionDetailView: View {
    let session: StrengthSession

    private var orderedExercises: [LoggedExercise] {
        session.exercises.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Date")
                    Spacer()
                    Text(session.loggedAt, format: Date.FormatStyle(date: .long, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                if let name = session.routineName {
                    HStack {
                        Text("Routine")
                        Spacer()
                        Text(name).foregroundStyle(.secondary)
                    }
                }
                if let mins = session.durationMinutes {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatDuration(mins)).foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(orderedExercises) { exercise in
                Section(exercise.name) {
                    let sorted = exercise.sets.sorted { $0.setNumber < $1.setNumber }
                    if sorted.isEmpty {
                        Text("No sets recorded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sorted) { s in
                            HStack {
                                Text("Set \(s.setNumber)")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(setSummary(s))
                                    .font(.body.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "135 lbs × 8" / "× 12" (no weight) / "135 lbs" (no reps) / "—".
    /// Honors nil ≠ 0: missing weight or reps shows as omitted, not as 0.
    private func setSummary(_ s: LoggedSet) -> String {
        let weight = s.weightLbs.map { formatWeight($0) }
        let reps   = s.reps.map { "\($0)" }
        switch (weight, reps) {
        case let (w?, r?): return "\(w) lbs × \(r)"
        case let (w?, nil): return "\(w) lbs"
        case let (nil, r?): return "× \(r)"
        case (nil, nil):    return "—"
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(w))"
            : String(format: "%.1f", w)
    }

    private func formatDuration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
