import SwiftUI
import SwiftData

/// v2.1a — Log a strength session. Pick a routine (or start blank). If a
/// routine is picked, its RoutineExercises pre-fill the editor's exercise
/// list with display-only target HINTS — those targets are NEVER copied
/// into stored LoggedSet values. The user adds LoggedSets one at a time
/// (weight × reps, auto-incrementing setNumber).
///
/// On Save: creates one StrengthSession with its LoggedExercises and nested
/// LoggedSets. Exercises with zero logged sets are skipped to keep history
/// clean.
struct LogSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\StrengthRoutine.order),
                  SortDescriptor(\StrengthRoutine.createdAt)])
    private var routines: [StrengthRoutine]

    /// nil = blank session (no routine attached).
    @State private var selectedRoutineID: UUID?
    @State private var exercises: [SessionExerciseDraft] = []
    @State private var durationStr: String = ""
    @State private var hasSeededFromRoutine = false

    /// Per-exercise editor state. Mirrors the model split: the draft holds
    /// the in-progress sets so adding/removing doesn't churn the context
    /// until Save.
    struct SessionExerciseDraft: Identifiable {
        let id = UUID()
        var name: String = ""
        /// Display-only — read from the source RoutineExercise. Never stored
        /// on the LoggedSet values.
        var targetSets: Int?
        var targetReps: Int?
        var targetWeightLbs: Double?
        var sets: [SetDraft] = []
    }

    struct SetDraft: Identifiable {
        let id = UUID()
        var weightStr: String = ""
        var repsStr: String = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    Picker("Pick a routine", selection: $selectedRoutineID) {
                        Text("Blank session").tag(UUID?.none)
                        ForEach(routines) { r in
                            Text(r.name).tag(UUID?.some(r.routineID))
                        }
                    }
                }

                ForEach($exercises) { $ex in
                    Section {
                        TextField("Exercise name", text: $ex.name)
                            .font(.body)

                        if let hint = targetHint(for: ex) {
                            Text("Target: \(hint)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if ex.sets.isEmpty {
                            Text("No sets logged yet.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(Array($ex.sets.enumerated()), id: \.element.id) { idx, $setDraft in
                                HStack(spacing: 8) {
                                    Text("Set \(idx + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 50, alignment: .leading)
                                    TextField("Weight", text: $setDraft.weightStr)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.center)
                                        .padding(6)
                                        .background(Color(.tertiarySystemGroupedBackground),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                    Text("lbs")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    TextField("Reps", text: $setDraft.repsStr)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .padding(6)
                                        .background(Color(.tertiarySystemGroupedBackground),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .onDelete { offsets in
                                ex.sets.remove(atOffsets: offsets)
                            }
                        }

                        Button {
                            ex.sets.append(SetDraft())
                        } label: {
                            Label("Add set", systemImage: "plus.circle")
                        }
                    }
                }
                .onDelete { offsets in
                    exercises.remove(atOffsets: offsets)
                }

                Section {
                    Button {
                        exercises.append(SessionExerciseDraft())
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                }

                Section {
                    HStack {
                        Text("Duration (optional)")
                        Spacer()
                        TextField("min", text: $durationStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Duration is informational only — strength sessions are NOT written to Apple Health (your Watch already captures calories).")
                }
            }
            .navigationTitle("Log session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: selectedRoutineID) { _, newID in
                seedFromRoutine(id: newID)
            }
            // v2.1b — Pre-select today's scheduled routine if one exists.
            // Only runs on first appear (hasSeededFromRoutine guards against
            // re-seeding if the user has already touched the picker).
            .onAppear {
                guard !hasSeededFromRoutine, selectedRoutineID == nil else { return }
                let map = StrengthSchedule.decode(scheduleJSON)
                let weekday = StrengthSchedule.weekday(for: .now)
                guard let id = map[weekday],
                      routines.contains(where: { $0.routineID == id }) else { return }
                selectedRoutineID = id
                // .onChange triggers seedFromRoutine which sets the flag.
            }
        }
    }

    // v2.1b — read-only access to the schedule JSON for pre-select.
    @AppStorage(StrengthSchedule.storageKey) private var scheduleJSON: String = "{}"

    /// Pre-fill exercises from a routine's RoutineExercises. Wipes any
    /// existing drafts — picking a routine resets the session, which is the
    /// natural mental model (you're starting fresh with a plan).
    private func seedFromRoutine(id: UUID?) {
        guard let id, let routine = routines.first(where: { $0.routineID == id }) else {
            exercises = []
            return
        }
        let sorted = routine.exercises.sorted { $0.order < $1.order }
        exercises = sorted.map { src in
            SessionExerciseDraft(
                name: src.name,
                targetSets: src.targetSets,
                targetReps: src.targetReps,
                targetWeightLbs: src.targetWeightLbs
            )
        }
        hasSeededFromRoutine = true
    }

    private var canSave: Bool {
        // At least one exercise with at least one logged set.
        exercises.contains { ex in
            !ex.name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !ex.sets.isEmpty
        }
    }

    /// "3×8 @ 135" / "3 sets" / "8 reps @ 135 lbs" — flexibly composed from
    /// whichever targets are non-nil. Display only; never stored.
    private func targetHint(for ex: SessionExerciseDraft) -> String? {
        var parts: [String] = []
        if let sets = ex.targetSets, let reps = ex.targetReps {
            parts.append("\(sets)×\(reps)")
        } else if let sets = ex.targetSets {
            parts.append("\(sets) sets")
        } else if let reps = ex.targetReps {
            parts.append("\(reps) reps")
        }
        if let w = ex.targetWeightLbs {
            let formatted = w.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(w))"
                : String(format: "%.1f", w)
            parts.append("@ \(formatted) lbs")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func save() {
        Haptic.success()

        let routineName: String? = {
            guard let id = selectedRoutineID,
                  let r = routines.first(where: { $0.routineID == id }) else { return nil }
            return r.name
        }()

        let duration = Double(durationStr.trimmingCharacters(in: .whitespaces))

        let session = StrengthSession(
            loggedAt: .now,
            routineName: routineName,
            durationMinutes: duration
        )
        context.insert(session)

        var exerciseOrder = 0
        for draft in exercises {
            let trimmedName = draft.name.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty, !draft.sets.isEmpty else { continue }

            let logged = LoggedExercise(name: trimmedName, order: exerciseOrder)
            logged.session = session
            context.insert(logged)
            exerciseOrder += 1

            for (idx, setDraft) in draft.sets.enumerated() {
                // Nil ≠ 0: empty weight/reps stay nil, never 0.
                let weight = Double(setDraft.weightStr.trimmingCharacters(in: .whitespaces))
                let reps   = Int(setDraft.repsStr.trimmingCharacters(in: .whitespaces))
                let s = LoggedSet(
                    weightLbs: weight,
                    reps: reps,
                    setNumber: idx + 1
                )
                s.exercise = logged
                context.insert(s)
            }
        }

        dismiss()
    }
}
