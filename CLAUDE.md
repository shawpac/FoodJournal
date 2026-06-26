# FoodJournal — Project Context

A personal iOS nutrition + fitness tracker (SwiftUI + SwiftData) for Mike Shaw's iPhone 17 Pro Max. Single-developer, no remote auto-push, no collaborators. Personal use only — not on App Store. Currently v2.1a.1.

**Display name vs internal name:** the app shows as **"MS Fitness"** on the home screen (set via `INFOPLIST_KEY_CFBundleDisplayName` in `project.pbxproj` as of v2.0). The bundle ID (`com.shawbler.FoodJournal`), Xcode project name (`FoodJournal.xcodeproj`), repo, and all source identifiers remain "FoodJournal" — do NOT rename them. Changing the bundle ID would orphan the user's existing SwiftData store.

Read SETUP.md for full feature reference. Read ROADMAP.md for pending work.

## Project location

`~/Desktop/my stuff/apps/foodjournal/foodjournal/`

Path has a space ("my stuff"). Always quote in shell:
```
cd ~/Desktop/"my stuff"/apps/foodjournal/foodjournal
```

## Tech stack

- iOS 18+ (deploys to iOS 26.4 on iPhone 17 Pro Max)
- Xcode 26.4 / Swift / SwiftUI / SwiftData
- **Free Apple Developer Team** — CANNOT enable iCloud/CloudKit (the capability doesn't appear in Xcode's picker). HealthKit DOES work on the free team — confirmed working in v1.8.2.
- External APIs: Open Food Facts (barcodes, free), Anthropic Claude Sonnet 4.6 (photo estimation), USDA FoodData Central (food search). API keys in Keychain via `KeychainStore`.
- Apple frameworks beyond SwiftUI/SwiftData: HealthKit (v1.8.2), UserNotifications (v1.8.1), VisionKit (barcode scanner), UIImagePickerController (camera capture).
- App config (late-night warning, meal schedules, reminders, smart-suggestion toggle, Health sync toggle) via `@AppStorage` / UserDefaults.

## Commit workflow

Use terminal, not Xcode's commit UI (unreliable for this project):

```
cd ~/Desktop/"my stuff"/apps/foodjournal/foodjournal
git add <specific files>
git commit -m "v1.X.Y: short description"
git log --oneline -5
```

Prefer staging specific files over `git add .` to avoid committing unrelated edits. **Commit after every feature ships, before moving on.** Past sessions have lost hours of work because commits were deferred and forgotten. Treat the commit step as required, not optional.

## Build / test workflow

User deploys to physical iPhone via Xcode (⌘R). You can edit code freely; user runs the build on device.

Schema changes (any new fields on `@Model` classes) require app reinstall on device. Protocol:
1. Tell user to export CSV first via Settings → Data → Export.
2. User long-presses app icon on phone → Remove App → Delete App.
3. User runs from Xcode (⌘R) for fresh install.

Schema-change versions so far: v1.8 (WaterEntry.pendingDeleteAt + new WeightEntry), v1.8.2 (healthSampleID on FoodEntry/WaterEntry/WeightEntry, importedFromHealth on WeightEntry), **v2.1a (7 new @Models: ExerciseRepEntry, StretchDay, StrengthRoutine, RoutineExercise, StrengthSession, LoggedExercise, LoggedSet — first @Relationship cascades in the schema)**. v1.8.1, v1.8.3, v1.8.4, v1.8.5, v1.8.6, v1.9, v2.0 (Workouts tab + display-name rename), v2.0.1 (CSV import), **v2.1a.1 (Apple Fitness split — view-only reorganization)** were schema-clean — no reinstall.

## Hard rules

- **Nil ≠ 0 anywhere.** Optional nutrient fields are `Double?`. Empty form input stays nil. Breakdown shows "–" for unknown, never "0". CSV exports nil as empty cells. Trends shows "based on N of M days" when partial coverage. Never silently convert nil to 0.

- **Never create files in Xcode with slashes in the name.** macOS converts slashes to colons → broken filenames like `Services:MealTimeHelper.swift`. Use plain identifiers, let Xcode place them via the New File dialog. The project uses synchronized folder groups, so files dropped into `FoodJournal/Services/` or `FoodJournal/Views/` via filesystem are auto-discovered — no .pbxproj edit needed.

- **Edit existing files directly via filesystem.** Don't generate large paste-blocks for the user. AuxViews.swift is now ~70KB; surgical paste-edits drift and silently fail. Direct edits avoid this entire class of bugs.

- **Don't push to a remote unless explicitly asked.** The repo has a GitHub remote at `github.com/shawpac/FoodJournal`, but commits stay local-only by default. Push is a deliberate action triggered by the user saying "push it," "add it to my github," etc. — never a side effect of shipping a feature.

- **Don't bypass the SwiftUI DatePicker `in: ...Date.now` constraint.** Future dates are blocked app-wide.

## Architecture invariants

- **`selectedDate` is shared between Today and Add tabs.** Owned by `RootView` as `@State`, passed as `@Binding` to `TodayView` and `AddFoodView`. `TrendsView` and `SettingsView` don't share — Trends has independent range pickers.

- **All food save paths thread `defaultDate: Date?` via mutation, not init.** Pattern:
  ```swift
  let entry = FoodEntry(...)  // init with default loggedAt = .now
  if defaultDate != nil { entry.loggedAt = pastDayLoggedAt }
  context.insert(entry)
  LibraryFoodUpsert.upsert(from: entry, in: context)
  HealthSync.onFoodSaved(entry)
  ```
  Mutation (not init parameter) avoids coupling to FoodEntry's positional init order.

- **Past-day flows now use an editable time picker (v1.8.3).** Each save sheet (ConfirmFoodView, ManualEntrySheet, PhotoLogSheet) holds `@State pastDayLoggedAt: Date` initialized to defaultDate (noon-of-day). When defaultDate != nil, a "Time logged" picker appears. SearchSheet quick-add intentionally skips (stays one-gesture, defaults to noon — fix via EditEntrySheet which now has both date + time pickers).

- **Every save path upserts into LibraryFood.** Always call `LibraryFoodUpsert.upsert(from: entry, in: context)` after `context.insert(entry)`. This maintains the personal library + useCount.

- **Hybrid storage in LibraryFood.** Per-100g if originally logged in grams, per-serving otherwise. `isPer100g` flag controls. SearchSheet quick-add stores `servingUnit: "100g"` to match ConfirmFoodView's format.

- **Soft delete via pendingDeleteAt.** `FoodEntry.pendingDeleteAt: Date?` AND `WaterEntry.pendingDeleteAt: Date?` AND `WeightEntry.pendingDeleteAt: Date?` (all added in v1.8). Powers 5-second undo on all three. Always exclude in queries: `$0.pendingDeleteAt == nil`.

- **Meal grouping is by `mealType` field, NOT hour-of-day.** Past-day entries are conventionally timestamped at noon when no explicit time was set. Hour-of-day display is mostly cosmetic.

- **Meal-time windows are user-configurable (v1.8).** `MealTimeHelper` reads breakfast/lunch/dinner start+end hours from UserDefaults. Defaults match the previous hardcoded schedule. Each window can wrap midnight.

- **Late-night warning is opt-in, configurable, applies to ALL save paths.** `MealTimeHelper.shouldWarnAboutLateSnack(meal:)` reads from UserDefaults. Wire into any new save path that creates snacks.

- **Apple Health sync is master-toggle gated (v1.8.2).** WRITES are gated by `healthSyncEnabled` in UserDefaults. DELETES always attempt when an entry has a populated `healthSampleID` (so turning sync off doesn't orphan previously-written samples). Wire `HealthSync.onFoodSaved/onWaterSaved/onWeightSaved` into every save path; wire `HealthSync.onFoodDeleting/onWaterDeleting/onWeightDeleting` BEFORE `context.delete(entry)` in every commit-delete path. EditEntrySheet calls `HealthSync.onFoodEdited` (delete old + write new).

- **Food entries are saved as individual quantity samples in Health, NOT as HKCorrelation.** HealthKit forbids requesting authorization for `HKCorrelationType.food`, which makes correlation-based deletes silently fail. `FoodEntry.healthSampleID` stores a JSON dict `{typeIdentifierRawValue: sampleUUID}` so deletes can route by type.

- **Smart suggestions are master-toggle gated (v1.8.6).** TodayView's banner only renders when `usualSuggestionsEnabled` (default true), on today, inside an active meal window (breakfast/lunch/dinner + 1h grace), with no entries already logged for that meal, and the user hasn't dismissed it for today.

- **Calories burned is read-only, queried on demand, never cached locally (v1.9).** `showCaloriesBurnedFromHealth` (`@AppStorage`, default false) gates every UI surface (Today energy strip, Trends Energy section, Net calories goal row in Settings, energy.csv in export). Reads come from `HealthService.readActiveEnergy / readBasalEnergy / readEnergySummary` and `readActiveEnergy(from:to:) / readBasalEnergy(from:to:)` for ranges. Today re-fetches on `selectedDate` change; Trends re-fetches on range change. Independent from the v1.8.2 write toggle (`healthSyncEnabled`) — user can have either, both, or neither on.

- **Net calories goal uses a sentinel-0 fallback.** Stored as `@AppStorage("netCaloriesGoal")` Double. Value `0` means "track the user's daily calorie goal automatically"; any other value is treated as a user override. The Settings field uses a computed Binding that returns `calorieGoal` when stored is 0 and writes through to AppStorage on edit. Same pattern in TodayView's `effectiveNetGoal`. Keeps v1.9 schema-clean (no new field on `UserGoals`).

- **Workouts are queried from HealthKit on demand, never cached locally (v2.0).** `WorkoutView` calls `HealthService.readWorkouts(from:to:)` on appear + pull-to-refresh; the result is `[HealthService.WorkoutSummary]` (plain struct, NOT a `@Model`). Auth is requested via the dedicated `requestWorkoutReadAuthorization()` helper on first appear. Active calories use `workout.statistics(for: .activeEnergyBurned)` (the deprecated `totalEnergyBurned` is NOT used). Distance maps `running/walking/hiking → distanceWalkingRunning` and `cycling → distanceCycling`; everything else is `nil`. Nil ≠ 0 applies to both — a workout with no energy or no distance samples shows "—".

- **CSV import is APPEND-ONLY with an empty-table guard per type (v2.0.1).** `CSVImportSheet` exposes a `.fileImporter` reachable from Settings → Data → Import data. It supports any subset of food/water/weight CSVs (detected by header sniff, not filename). Before processing a given file's rows, the corresponding table is checked for any non-soft-deleted entries; if non-empty, the file is skipped with a user-facing message and zero rows are inserted. There is intentionally NO dedupe/merge — the user's contract is "import only into a freshly reinstalled (empty) app." Imported `FoodEntry` rows call `LibraryFoodUpsert.upsert(from:in:)` like every other save path so the search library + useCount rebuilds. Import deliberately does NOT call `HealthSync` — these are historical restorations, not new logs; re-syncing would duplicate or orphan Health samples. Original `source` is preserved per-row from the CSV (column index 5); only blank source cells fall back to `"import"`. The energy.csv export is recognized but reported as "not stored locally" — energy is read-only from Health.

- **CSV importer is the exact inverse of CSVExportSheet (v2.0.1).** Same files, same column order, same headers, same `yyyy-MM-dd` / `HH:mm` POSIX date format, same RFC 4180 quoting. Critical invariant: empty optional cells parse to `Double? = nil`, NEVER 0. Empty required cells (name, loggedAt, servings, calories, protein/carbs/fat, amountOz, weightLbs) mark the row malformed and skip it. The exporter writes nutrient TOTALS (per-serving × servings); the importer divides back by servings to recover per-serving storage. Servings ≤ 0 is treated as malformed (avoids divide-by-zero).

- **Strength + daily-tracker data is in-app only (v2.1a).** ExerciseRepEntry, StretchDay, StrengthRoutine/RoutineExercise, StrengthSession/LoggedExercise/LoggedSet have NO HealthKit fields and intentionally do NOT call HealthSync. Two reasons: (1) HealthKit has no schema for weight/reps/sets, and (2) the user wears an Apple Watch that already captures calorie burn passively — writing a workout from in-app strength logging would double-count against Today's energy strip and Trends. Do NOT add HK writes to these models. The "no duplicate calorie counting" rule is the durable design constraint.

- **StrengthSession → LoggedExercise → LoggedSet is the first two-level cascade in the schema (v2.1a).** Both relationship lines declare `@Relationship(deleteRule: .cascade, inverse: \Child.parent)` on the parent side; the child carries the back-pointer with no annotation. Same pattern on StrengthRoutine → RoutineExercise. Apple's docs recommend declaring the inverse on whichever side owns the cascade rule, so the rule and inverse stay together. When adding a third level later, follow this pattern — declare `inverse:` on the new parent, plain back-pointer on the new child.

- **LoggedExercise stores the exercise NAME as a String snapshot, NOT a relationship to RoutineExercise (v2.1a).** This is deliberate: editing a routine (rename, change targets) or deleting it entirely does NOT retroactively change session history. RoutineExercise targets are display-only hints during LogSessionSheet — never copied into stored LoggedSet values. The "history is immutable" rule means RoutineEditorSheet can safely use replace-all on save (delete existing RoutineExercises, insert fresh ones) without orphaning past sessions.

## Recurring pitfalls (do not re-make these mistakes)

- **HealthKit: do NOT include `HKCorrelationType(.food)` in `requestAuthorization`'s `toShare:` set.** It crashes with `NSInvalidArgumentException: Authorization to share the following types is disallowed: HKCorrelationTypeIdentifierFood`. Confirmed during v1.8.2 development. Only request quantity types.

- **HealthKit: correlation-based food entries are not deletable via predicate.** We save individual quantity samples for each nutrient (one HK row per nutrient per meal) so we can delete each by type+UUID later. See `HealthService.writeFoodEntry` / `deleteFoodSamples`. Less pretty in Health's "Show All Data" view; per-nutrient summaries are unaffected.

- **FoodEntry init order** (matters for direct construction): `name, brand, servings, servingUnit, calories, protein, carbs, fat, saturatedFat, polyunsaturatedFat, monounsaturatedFat, transFat, fiber, sugar, cholesterol, sodium, potassium, vitaminA, vitaminC, vitaminD, calcium, iron, magnesium, loggedAt, mealType, source, barcode, pendingDeleteAt, healthSampleID`. Fat-detail (sat/poly/mono/trans) comes BEFORE fiber/sugar.

- **WaterEntry init order:** `amountOz, loggedAt, pendingDeleteAt, healthSampleID`.

- **WeightEntry init order:** `weightLbs, loggedAt, pendingDeleteAt, healthSampleID, importedFromHealth`.

- **ConfirmFoodView.Prefill has no `servingUnit` member.** ConfirmFoodView builds the unit string internally as `"\(Int(grams))g"`. For direct FoodEntry creation from a Prefill, hardcode `"100g"` to match.

- **RelogSheet is dormant.** Kept in codebase but unreachable from UI. Has been kept in lockstep with v1.7.1 defaultDate threading and v1.8.2 HealthSync wiring for consistency; safe to wire-in fresh save paths to it but don't rely on it being a reachable user flow.

- **`@Query` filters are evaluated against current SwiftData state.** Sheets that have their own `@Query` (like NutritionBreakdownSheet, WeightEntriesSheet, WaterEntriesSheet) must filter by `pendingDeleteAt == nil` AND the relevant date scope, or they'll display stale/inconsistent data.

- **TaskGroup-based timeouts on HK calls don't actually cancel the underlying HKHealthStore work.** The HK auth API doesn't honor `Task.cancel()`. Don't add fake timeouts that desync UI state.

- **HealthKit read permissions cannot be probed for grant state.** Apple intentionally returns "not determined" instead of "denied" on `authorizationStatus(for:)` for read-only types — privacy protection. For the v1.9 "Show calories burned" toggle, we can detect ERRORS from `requestAuthorization` (HK unavailable, etc.) but we CANNOT detect user denial. The handler reverts the toggle only on actual error; if the user denies in the prompt, the toggle stays on and the UI shows "—" because reads return no samples. Don't try to invent denial detection by probing — it'll be unreliable.

- **Nil ≠ 0 applies to burn data too (v1.9).** Days with no Active Energy samples (watch off your wrist) MUST be excluded from averages, never treated as zero. `HealthService.readActiveEnergy(from:to:)` and `readBasalEnergy(from:to:)` return dicts where absent days are absent (not present with value 0). Trends' Avg Net only counts days with BOTH consumed and burn data. CSV's energy.csv leaves nil cells empty.

## File map (where to look)

- `FoodJournalApp.swift` — entry point, SwiftData container with **14 model types** (7 originals + 7 v2.1a strength/daily), owns NotificationCoordinator + registers as UN delegate.
- `Models/Models.swift` — all `@Model` classes: originals (FoodEntry, UserGoals, CachedFood, WaterEntry, CachedPhotoEstimate, LibraryFood, WeightEntry) + v2.1a strength/daily (ExerciseRepEntry, StretchDay, StrengthRoutine, RoutineExercise, StrengthSession, LoggedExercise, LoggedSet — with @Relationship cascades + inverses). Plus `LibraryFoodUpsert` helper + `FoodFormat` enum.
- `Services/`
  - `MealTimeHelper.swift` — meal-window config (UserDefaults-backed, configurable in Settings since v1.8); late-night warning logic.
  - `LibraryService.swift`, `USDAService.swift`, `OpenFoodFactsService.swift` — search + product lookup.
  - `ClaudeVisionService.swift` — photo → nutrition estimate; supports multi-image (v1.8.5).
  - `KeychainStore.swift` — parameterized key storage (anthropic + usda).
  - `NotificationService.swift` (v1.8.1) — daily meal reminder scheduling.
  - `NotificationCoordinator.swift` (v1.8.1) — `@Observable` UN delegate for foreground display + tap-to-deep-link.
  - `HealthService.swift` (v1.8.2, extended in v1.9 and v2.0) — contains both `HealthService` (low-level HK ops) and `HealthSync` (write orchestration for v1.8.2). Read the file's header comments for the correlation-type gotcha. v1.9 added active/basal energy reads (single-day + range) and `requestEnergyReadAuthorization()`. v2.0 added `WorkoutSummary` (plain struct), `readWorkouts(from:to:)`, `requestWorkoutReadAuthorization()`, and an `activityInfo(for:)` mapping helper for 12+ HKWorkoutActivityType values → (display name, SF Symbol).
  - `UsualSuggestionService.swift` (v1.8.6) — heuristic for "your usual breakfast/lunch/dinner" suggestion banner.
- `Views/RootView.swift` — TabView root with 5 tabs (Today/Add/Trends/**Workouts** (v2.0, tag 3)/Settings), hoisted `selectedDate`, watches `NotificationCoordinator.pendingMealOpen` for deep-link to MealDetailSheet (deep-link still targets tag 0).
- `Views/WorkoutView.swift` (v2.0, extended in v2.1a, split in v2.1a.1) — Workouts tab. Composable section structure: today summary card + **Apple Fitness section showing only TODAY inline** with a "See previous workouts ›" `NavigationLink` to `WorkoutHistoryView` (v2.1a.1) + **Daily section** (pushup/situp append cards with append + count display + long-press to manage individual bursts; stretch toggle card) + **Strength section** (3 nav rows opening Routines / Log a session / History sheets). Reads from `HealthService.readWorkouts` on appear + pull-to-refresh. Self-contained state; does NOT share RootView's selectedDate (matches Trends/Settings precedent).
- `Views/WorkoutHistoryView.swift` (v2.1a.1) — full-page Apple Fitness history pushed from the Workouts tab. Receives the parent's pre-filtered `previousWorkouts` array (excludes today). Does NOT issue its own HK query — reuses what the parent already fetched. Date-grouped list newest first; "Today" case omitted from `dayLabel` since today is excluded by construction.
- `Views/DailyRepsSheet.swift` (v2.1a) — manages today's individual ExerciseRepEntry bursts for one kind (`pushups` or `situps`). Mirrors WaterEntriesSheet exactly: list, swipe-delete with 5s undo toast, commit on dismiss.
- `Views/RoutinesSheet.swift` (v2.1a) — list + create + edit + delete StrengthRoutine templates. Cascade-deletes their RoutineExercises. Nested `RoutineEditorSheet` for name + ordered exercise list with optional target sets/reps/weight. Uses replace-all on edit (safe — LoggedExercise stores name snapshots).
- `Views/LogSessionSheet.swift` (v2.1a) — log a StrengthSession. Pick routine (or blank); pre-fills exercise list from routine showing target hints (display-only, never copied into stored LoggedSet values). Adds LoggedSets one at a time with auto-incrementing setNumber. Empty exercises skipped on save. Optional durationMinutes field.
- `Views/SessionHistorySheet.swift` (v2.1a) — reverse-chrono list of past StrengthSessions with metadata; tap → read-only SessionDetailView. Swipe-delete with 5s undo at the list level (cascade fires through LoggedExercises → LoggedSets).
- `Views/TodayView.swift` — date-navigable dashboard. Hosts WaterEntriesSheet (nested) + MealDetailSheet (nested). Smart-suggestion banner (v1.8.6) sits above the daily totals card. v1.9 energy strip (Consumed / Burned / Net / Active) sits between daily totals and water, gated by `showCaloriesBurnedFromHealth`. Meal cards show P/C/F line below calories (v1.8.4). EntryRow recognizes `source == "suggestion"` for sparkles icon. `StatTile.progress` is `Double?`; nil hides the bar (used by Consumed/Burned/Active).
- `Views/AddFoodView.swift` — date-aware add tab + past-day banner + MostUsedSheet (nested).
- `Views/TrendsView.swift` — range picker, per-section averages, Weight section (always visible since v1.8), v1.9 Energy section (Avg Active / Avg Total Burned / Avg Net) shown when `showCaloriesBurnedFromHealth` is on (parallel to Weight, outside the food-data gate), Distribution by meal section (v1.8.4), nested WeightEntriesSheet for log/manage.
- `Views/SearchSheet.swift` — library + USDA search + library swipe-add (v1.7.3) with HealthSync wiring (v1.8.2).
- `Views/NutritionBreakdownSheet.swift` — full 19-nutrient breakdown by selectedDate.
- `Views/BarcodeScannerSheet.swift`, `Views/PhotoLogSheet.swift` — scanner + photo log. PhotoLogSheet was rewritten in v1.8.5 around `images: [UIImage]` for multi-photo.
- `Views/CSVExportSheet.swift` — exports food/water/weight CSVs (v1.8.2 added weight; v1.9 adds energy.csv when `showCaloriesBurnedFromHealth` is on — per-day active/basal/total/consumed/net columns, nil → empty cell).
- `Views/CSVImportSheet.swift` (v2.0.1) — inverse of CSVExportSheet. `.fileImporter` for any subset of food/water/weight CSVs (header-sniff detection). Per-type empty-table guard (aborts the file's import if non-soft-deleted rows already exist for that type). RFC 4180 parser, POSIX yyyy-MM-dd / HH:mm formatters. Food import calls `LibraryFoodUpsert.upsert`, preserves CSV `source` column, intentionally does NOT fire HealthSync.
- `Views/NutrientGoalsSheet.swift` — editable goals for the 14 secondary nutrients.
- `Views/AuxViews.swift` — ConfirmFoodView, ManualEntrySheet, EditEntrySheet, SettingsView (Meal time schedule, Reminders, Smart suggestions, Apple Health sections; Data section has Export + **Import (v2.0.1)** + Reset library), AnthropicKeySheet, USDAKeySheet, RelogSheet (dormant), dismissKeyboard, SelectAllOnFocus modifier, Haptic helper. Large file (~70KB) — search by `struct` keyword to navigate.

## Manual Xcode steps locked in (don't repeat in new sessions)

- **HealthKit capability** is enabled (Signing & Capabilities → HealthKit). `FoodJournal.entitlements` contains `com.apple.developer.healthkit = true`.
- **Info.plist privacy strings** for `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` live in `project.pbxproj` as `INFOPLIST_KEY_*` build settings (Xcode's Info tab writes there for modern projects).
- Future sessions don't need to redo these.

## When user says "let's ship vX.Y"

1. Confirm scope with user. For schema changes, also confirm CSV export and reinstall plan.
2. Read relevant files; don't ask for paste-backs unless absolutely needed.
3. Make edits directly via filesystem.
4. Run `xcodebuild` if it'd help catch errors before handing off (not strictly required).
5. Tell user to ⌘R and test on device. Give clear test steps.
6. On user's "it works" confirmation, commit with descriptive message.
7. If feature is significant, update SETUP.md and ROADMAP.md in the same or follow-up commit.

## Style and tone (user preferences)

Mike prefers direct communication, no preamble, no filler. Match response length to query complexity. Banned words/phrases: "great question," "delve," "foster," "landscape," "leverage" (outside finance), "crucial," "it's worth noting." No em dashes. Use confidence tags (HIGH/MODERATE/LOW) on substantive technical claims. Counter-arguments where genuine; skip when only weak counters exist.
