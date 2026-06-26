import SwiftUI
import SwiftData

/// v2.1a — Manage reusable StrengthRoutine templates. List + create + edit +
/// delete (cascade-deletes the routine's RoutineExercises). Templates store
/// optional targets per exercise (sets / reps / weight) that show as DISPLAY
/// HINTS during session logging — they are never copied into stored set
/// values.
struct RoutinesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\StrengthRoutine.order),
                  SortDescriptor(\StrengthRoutine.createdAt)])
    private var routines: [StrengthRoutine]

    @State private var editingRoutine: StrengthRoutine?
    @State private var showingCreateSheet = false

    var body: some View {
        NavigationStack {
            List {
                if routines.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "dumbbell.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No routines yet")
                                .font(.headline)
                            Text("Create a routine with the exercises you usually do, then log sessions against it.")
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
                        ForEach(routines) { routine in
                            Button {
                                editingRoutine = routine
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(routine.name)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Text("\(routine.exercises.count) exercise\(routine.exercises.count == 1 ? "" : "s")")
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
                        .onDelete { offsets in
                            for index in offsets {
                                let r = routines[index]
                                // Cascade deletes the RoutineExercises.
                                context.delete(r)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                RoutineEditorSheet(mode: .create)
            }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorSheet(mode: .edit(routine))
            }
        }
    }
}

/// Create or edit a single routine. On save:
///   - Create: insert a fresh StrengthRoutine and its RoutineExercises.
///   - Edit:   delete the existing RoutineExercises (cascade-safe by virtue
///             of context.delete on each) and replace with the editor's
///             working list. Past StrengthSessions don't reference these
///             exercises directly (LoggedExercise stores a name snapshot),
///             so replacing is safe — no orphaned history.
struct RoutineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    enum Mode {
        case create
        case edit(StrengthRoutine)
    }

    let mode: Mode

    @State private var name: String = ""
    @State private var rows: [ExerciseRow] = []

    /// Lightweight editor row — kept separate from RoutineExercise so adds /
    /// removes / reorders during editing don't touch the model context until
    /// Save fires.
    struct ExerciseRow: Identifiable {
        let id = UUID()
        var name: String = ""
        var targetSetsStr: String = ""
        var targetRepsStr: String = ""
        var targetWeightStr: String = ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine name") {
                    TextField("e.g. Push day A", text: $name)
                }

                Section {
                    if rows.isEmpty {
                        Text("Add at least one exercise.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Exercise name", text: $row.name)
                                    .font(.body)
                                HStack(spacing: 8) {
                                    targetField("Sets", text: $row.targetSetsStr, suffix: "")
                                    targetField("Reps", text: $row.targetRepsStr, suffix: "")
                                    targetField("Weight", text: $row.targetWeightStr, suffix: "lbs")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            rows.remove(atOffsets: offsets)
                        }
                        .onMove { source, destination in
                            rows.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Targets are optional — leave blank if you don't have a fixed plan. They show as hints when you log a session.")
                }

                Section {
                    Button {
                        rows.append(ExerciseRow())
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    private var navTitle: String {
        switch mode {
        case .create: return "New routine"
        case .edit:   return "Edit routine"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        rows.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func targetField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack(spacing: 4) {
            TextField(label, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8))
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadIfEditing() {
        if case .edit(let routine) = mode {
            name = routine.name
            let sorted = routine.exercises.sorted { $0.order < $1.order }
            rows = sorted.map { ex in
                ExerciseRow(
                    name: ex.name,
                    targetSetsStr:   ex.targetSets.map(String.init) ?? "",
                    targetRepsStr:   ex.targetReps.map(String.init) ?? "",
                    targetWeightStr: ex.targetWeightLbs.map { String($0) } ?? ""
                )
            }
        }
    }

    private func save() {
        Haptic.success()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let cleaned = rows
            .map { row -> ExerciseRow in
                var copy = row
                copy.name = row.name.trimmingCharacters(in: .whitespaces)
                return copy
            }
            .filter { !$0.name.isEmpty }

        switch mode {
        case .create:
            let routine = StrengthRoutine(name: trimmedName)
            context.insert(routine)
            attachExercises(cleaned, to: routine)
        case .edit(let routine):
            routine.name = trimmedName
            // Replace-all: drop existing target lines, then insert fresh.
            // Past sessions snapshot names into LoggedExercise so editing /
            // deleting routine exercises is safe — no orphan history.
            for ex in routine.exercises {
                context.delete(ex)
            }
            attachExercises(cleaned, to: routine)
        }
        dismiss()
    }

    private func attachExercises(_ source: [ExerciseRow], to routine: StrengthRoutine) {
        for (idx, row) in source.enumerated() {
            let ex = RoutineExercise(
                name: row.name,
                targetSets:      Int(row.targetSetsStr.trimmingCharacters(in: .whitespaces)),
                targetReps:      Int(row.targetRepsStr.trimmingCharacters(in: .whitespaces)),
                targetWeightLbs: Double(row.targetWeightStr.trimmingCharacters(in: .whitespaces)),
                order: idx
            )
            ex.routine = routine
            context.insert(ex)
        }
    }
}
