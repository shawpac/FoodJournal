import SwiftUI
import SwiftData

/// v2.1b — Weekly schedule editor. 7 rows (Mon…Sun in display order; stored
/// by Calendar.weekday 1=Sun…7=Sat). Each row is a Picker over the current
/// StrengthRoutines plus a Rest option. Storage is a single `@AppStorage`
/// JSON string driven via `StrengthSchedule`.
///
/// Schema-clean — no @Model. If a stored routineID no longer resolves
/// (routine was deleted), that day reads as Rest. The Picker also surfaces
/// any unresolved-but-currently-stored UUIDs as "Rest" by virtue of the
/// resolution layer.
struct ScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// All routines, sorted by their `order` then by `createdAt`. Mirrors
    /// the sort RoutinesSheet uses.
    @Query(sort: [SortDescriptor(\StrengthRoutine.order),
                  SortDescriptor(\StrengthRoutine.createdAt)])
    private var routines: [StrengthRoutine]

    @AppStorage(StrengthSchedule.storageKey) private var scheduleJSON: String = "{}"

    /// Display ordering puts Monday first (US fitness convention). Storage
    /// stays Calendar.weekday (1=Sun…7=Sat).
    private let displayOrder: [Int] = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(displayOrder, id: \.self) { weekday in
                        weekdayRow(weekday: weekday)
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Pick a routine for each day or leave it as Rest. The Workouts tab shows today's pick and Log a session pre-selects it.")
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func weekdayRow(weekday: Int) -> some View {
        let map = StrengthSchedule.decode(scheduleJSON)
        let resolved = map[weekday].flatMap { id in
            routines.first(where: { $0.routineID == id })
        }
        return Picker(weekdayName(weekday), selection: binding(forWeekday: weekday)) {
            Text("Rest").tag(UUID?.none)
            ForEach(routines) { routine in
                Text(routine.name).tag(UUID?.some(routine.routineID))
            }
            // If the user once selected a routine that has since been deleted,
            // the saved ID won't match any current routine. Show it as Rest
            // by default — but the `resolved` lookup above already returns
            // nil in that case, so the binding sees no current selection.
            // We deliberately do NOT surface the dangling UUID anywhere.
        }
        .pickerStyle(.menu)
        .tint(resolved == nil ? .secondary : .primary)
    }

    /// Binding that reads/writes the AppStorage-backed schedule for one day.
    /// Get returns the resolved routine's ID, or nil for Rest / dangling.
    /// Set updates the JSON and the SwiftUI tree re-renders via @AppStorage.
    private func binding(forWeekday weekday: Int) -> Binding<UUID?> {
        Binding<UUID?>(
            get: {
                let map = StrengthSchedule.decode(scheduleJSON)
                guard let stored = map[weekday] else { return nil }
                // Resolve: return nil for dangling IDs so the picker shows Rest.
                return routines.contains(where: { $0.routineID == stored }) ? stored : nil
            },
            set: { newID in
                let map = StrengthSchedule.decode(scheduleJSON)
                let updated = StrengthSchedule.setting(map, routineID: newID, forWeekday: weekday)
                scheduleJSON = StrengthSchedule.encode(updated)
            }
        )
    }

    private func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "—"
        }
    }
}
