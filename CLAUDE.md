# FoodJournal — Project Context

A personal iOS nutrition + fitness tracker (SwiftUI + SwiftData) for Mike Shaw's iPhone 17 Pro Max. Single-developer, no remote auto-push, no collaborators. Personal use only — not on App Store. Currently v2.3a.

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
- **Free Apple Developer Team** — CANNOT enable iCloud/CloudKit (the capability doesn't appear in Xcode's picker). HealthKit DOES work on the free team — confirmed working in v1.8.2. **CANNOT enable `com.apple.developer.healthkit.access = ["health-records"]`** (Clinical / Verifiable Health Records) — same gate as CloudKit. Confirmed during v2.3a: free team can't sign with this entitlement (provisioning profile generation fails with "Personal development teams … do not support the HealthKit Access (Verifiable Health Records) capability"). Apple Health → MS Fitness FHIR ingestion is therefore deferred to v2.3b when/if a paid Developer Program account is in place. The v2.3a workaround: take a screenshot of Health → Browse → Lab Results → [provider] → [panel] and feed it through the existing photo-import path; Claude transcribes the same data.
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

Schema-change versions so far: v1.8 (WaterEntry.pendingDeleteAt + new WeightEntry), v1.8.2 (healthSampleID on FoodEntry/WaterEntry/WeightEntry, importedFromHealth on WeightEntry), v2.1a (7 new @Models: ExerciseRepEntry, StretchDay, StrengthRoutine, RoutineExercise, StrengthSession, LoggedExercise, LoggedSet — first @Relationship cascades in the schema), **v2.3a (2 new @Models: LabPanel + LabResult — first medical data; cascade matches the v2.1a strength pattern)**. v1.8.1, v1.8.3, v1.8.4, v1.8.5, v1.8.6, v1.9, v2.0 (Workouts tab + display-name rename), v2.0.1 (CSV import), v2.1a.1 (Apple Fitness split — view-only reorganization), v2.1b (weekly strength schedule + per-exercise trends — view + AppStorage only), v2.2 (Health Data tab + 5-tab bar reorg — view + HealthKit reads only), v2.2.1 (Open Food Facts text search + merge/dedupe/source tags — view + service only), v2.2.2 (typed-context field on photo estimate — view + ClaudeVisionService only), v2.2.3 (CSV export + import for strength + daily-tracker tables — extends CSVExportSheet + CSVImportSheet only) were schema-clean — no reinstall.

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

- **Weekly strength schedule is @AppStorage-backed JSON (v2.1b).** Single key `strengthWeeklySchedule` holds a JSON-encoded `[String: String]` map (weekday "1"…"7" per `Calendar.weekday`, 1 = Sunday → routineID UUID string). Decoded at render time via `StrengthSchedule.decode(_:)`. **Dangling stored IDs** (routine since deleted) resolve to nil and render as Rest — never crash, never surface the orphan UUID. ScheduleSheet's row Binding intentionally returns nil for dangling IDs so the Picker shows Rest. Today's pick surfaces on WorkoutView's Strength section header and pre-selects in LogSessionSheet via `onAppear`.

- **Strength trend stats are computed INDEPENDENTLY per session (v2.1b).** In `StrengthTrendsSheet`, the per-session **top-set weight** (max non-nil `weightLbs`) and **est. 1RM** (max Epley `weight × (1 + reps/30)` over sets with BOTH non-nil) come from potentially DIFFERENT sets in the same session. Do NOT refactor to pick a single "best set" and derive both from it — that would silently break the heaviest-lift vs highest-rep-volume distinction. Sets with nil weight OR nil reps are excluded from the e1RM math; sets with nil weight are excluded from top-set math.

- **Health metrics use a single descriptor list (v2.2).** `HealthService.healthMetrics: [HealthMetric]` is the source of truth for every single-value vital — adding a new metric is a one-line entry. Generic readers `readMetricToday` and `readMetricByDay` dispatch on `MetricAggregation` (`.average` for rate-style metrics, `.sum` for cumulative counters, `.latest` for sparsely-updated metrics like VO2 max and wrist temp). Sleep (`SleepNight` + bespoke `readLastNightSleep` / `readSleepDurationByNight`) and BP (`BPReading` + bespoke `readBloodPressureLatest` / `readBloodPressureSeries`) are exceptions because they don't fit the single-value pattern. Health data is read on demand, NEVER cached locally — same invariant as v1.9 energy and v2.0 workouts.

- **Tab bar holds exactly 5 tabs (v2.2 reorg).** Order: **Food (tag 0) · Workouts (1) · Health Data (2) · Trends (3) · Settings (4)**. iOS overflows to a "More" tab beyond 5 — DO NOT add a 6th without consolidating. The `Add` tab was removed in v2.2 (the user adds food via meal cards on the Food tab, not via a dedicated tab). The notification deep-link still targets `selectedTab = 0` (= Food = TodayView). `AddFoodView.swift` is left in the project but unreferenced — safe to delete in a later cleanup.

- **Food search has two remote sources, queried concurrently (v2.2.1).** USDA FoodData Central (lab-quality, requires personal API key) and Open Food Facts (crowd-sourced, no key, denser branded coverage). Both run in parallel from the same 300ms debounce in `SearchSheet.performRemoteSearch`. One failing source does NOT block the other — partial coverage beats no coverage. Results merge into ONE ranked list with per-row source tags (`USDA` green / `OFF` orange). Cross-source dedupe collapses near-duplicates on name + brand + ±15% calorie tolerance, PREFERRING USDA on collisions. The dedupe heuristic + relevance scorer are intentionally readable and tunable — see `mergeAndDedupe(_:_:query:)` in SearchSheet.

- **Branded toggle gates OFF AND USDA Branded (v2.2.1).** OFF's catalog is overwhelmingly branded; querying it for `includeBranded=false` would clutter the generic-food experience. Off → USDA generic only (Foundation / SR Legacy / Survey). On → USDA generic + USDA Branded + all OFF results. The toggle's footer text in SearchSheet documents this.

- **SearchSheet cancels its in-flight remote fetch on every keystroke (v2.2.1).** The Task reference lives in `@State remoteFetchTask`. Cancellation propagates through Swift structured concurrency to the URLSession data tasks inside. This prevents rapid typing from piling concurrent HTTPS requests onto the same HTTP/2 connection — a real fix for the api.data.gov nginx-400 symptom that appeared with v2.2.1's two-source concurrency. `CancellationError` is suppressed inside the per-source closures so cancelled fetches don't surface as user-facing errors.

- **Photo estimate accepts optional user-typed context (v2.2.2).** `ClaudeVisionService.estimate(images:userContext:apiKey:)` and `prepareImages(_:userContext:)` take an optional `String userContext`. When non-empty, a context block is prepended to the prompt instructing Claude to treat user-provided weights, names, brands, and prep details as MORE authoritative than what it would infer from the photo. The context is ALSO folded into the cache hash (SHA256 over `imageHash + "|ctx|" + lowercased context`) so the same photo with different context misses cache and triggers a fresh Claude call. **Empty context preserves the v1.8.5 cache hash byte-for-byte** — existing cached estimates keep hitting. PhotoLogSheet's `contextField` lives between the photo strip and the Analyze button; stays visible during/after analysis so the user can refine and Re-analyze.

- **Strength + daily-tracker tables have CSV export + import (v2.2.3).** Closes the v2.0.1 gap: every persisted model except the cache tables is now reinstall-survivable. Four new files alongside food/water/weight/energy: `strength-sessions.csv` (one row per LoggedSet — flattens the two-level cascade unambiguously), `strength-routines.csv` (one row per RoutineExercise template line), `rep-entries.csv` (pushups/situps bursts), `stretch-days.csv` (daily binary). Same conventions as v2.0.1: per-type empty-table guard, header-sniff detection, RFC 4180 quoting, POSIX `yyyy-MM-dd` / `HH:mm` formatters, append-only, no dedupe. **Strength sessions and rep bursts are range-filtered; routines export in FULL** regardless of range (templates, not events — losing old routines to a short export window would be unhelpful). **Zero-set exercises and zero-exercise routines aren't exported** (consistent with LogSessionSheet's save-time skip — they shouldn't exist, and if they do, they round-trip as omitted). On import, strength sessions group rows back into StrengthSession → LoggedExercise → LoggedSet by (`session_date`, `session_time`, `routine_name`, `duration_minutes`) at the session level, then (`exercise_name`, `exercise_order`) within a session. Routines group by (`routine_name`, `routine_order`, `created_at`). Nil ≠ 0 still applies to every optional field: `weight_lbs`, `reps`, `target_sets`, `target_reps`, `target_weight_lbs`, `duration_minutes`, `routine_name`. Imports do NOT touch HealthKit (the v2.1a "in-app only" rule) and do NOT call any upserter (no LibraryFood analog exists for these models).

- **Lab results are DISPLAY-AND-FLAG only — NEVER INTERPRETATION (v2.3a).** This is the non-negotiable rule for the LabPanel / LabResult surface. For every value the app stores the value, the unit, and the lab's OWN printed reference range, and flags in/out-of-range using THAT range. It must NEVER tell the user what an abnormal value means, whether to worry, what action to take, or offer any medical opinion — no "high," no "low," no "elevated," no "consult your doctor about X," no app-invented ranges. A result with no printed numeric range shows NO flag, not a guessed one. The single out-of-range indicator string in `LabResultRow` is "out of range" — neutral, factual, no commentary. This rule applies to every surface that displays a lab value (panel detail, marker trends, photo review, Apple Health import preview). Claude's lab-extraction prompt in `ClaudeVisionService.extractLabReport` mirrors the constraint: transcription only, no interpretation, no unit conversion, no invented ranges. The FHIR parser in `ClinicalLabImporter` follows the same rule — it transcribes what providers sent.

- **Lab data has TWO import paths in v2.3a — manual and photo/PDF.** Both save the same `LabPanel → LabResult` shape via the same insert pattern (parent insert + child back-pointer + child insert), so panel detail / marker trends / merge tool surfaces don't care where a row came from. `LabPanelManualSheet` (free typing) + `LabPhotoImportSheet` (Claude transcribes a JPEG OR a PDF → mandatory human review → save). The PDF variant lands on Claude's `document` content type and reads multi-page reports natively; lab reports up to 32 MB / 100 pages fit. **Apple Health clinical-records (FHIR) direct ingestion was originally planned for v2.3a but pulled because free dev team can't sign with the `health-records` entitlement.** Free-team workaround: export PDF from Apple Health → Browse → Lab Results → Share → PDF, then import that PDF directly via the photo/PDF path. The `fhirID: String?` field on `LabResult` was left on the schema for the eventual paid-membership FHIR rebuild (cheap to keep, nil for manual + photo/PDF entries).

- **Lab values + units + reference ranges store EXACTLY as the source reports them (v2.3a).** No unit conversion ever — mg/dL stays mg/dL; mmol/L stays mmol/L. Converting medical values is dangerous and out of scope. Numeric values live on `LabResult.value: Double?`; qualitative results ("Negative", "Detected", ">100", "<0.1") live on `LabResult.valueText: String?` — never coerce qualitative to a number. The two are mutually exclusive on a row; nil-and-nil means incomplete and renders "–". Reference range is split: `refRangeLow` + `refRangeHigh` for the simple numeric case, and `refRangeText` preserves verbatim non-simple ranges. The neutral in/out-of-range flag fires ONLY when a numeric value compares to a numeric low or high bound; `refRangeText` alone (e.g. "<5.7", "Negative") doesn't drive a flag because interpreting inequality text is interpretation, which is out of scope. **Nil ≠ 0 is especially critical here**: a fake 0 substituted for an absent value could read as a catastrophic result. Every optional field on LabResult stays nil when absent.

- **Marker grouping for trends: auto-merge on EXACT normalizedName, manual-merge for non-exact (v2.3a).** `LabMarker.normalize(testName)` lowercases and strips all non-alphanumeric chars: "HbA1c" / "Hb-A1c" / "HB A1C" all → "hba1c" and auto-merge. Differently-named tests like "Hemoglobin A1c" ("hemoglobina1c") and "HbA1c" ("hba1c") stay SPLIT until the user explicitly merges them via `LabMarkerMergeSheet`. The merge map is a single `@AppStorage("labMarkerAliases")` JSON `[String: String]` from normalizedName → canonical normalizedName, with cycle-safe chain following in `LabMarkerAliases.canonical(of:aliases:)`. Lighter than a 17th @Model. A wrong auto-merge (two different tests on one trend) is worse than a split — that's why non-exact matches require explicit user action.

- **Photo lab import has MANDATORY human review (v2.3a).** `ClaudeVisionService.extractLabReport` returns an `ExtractedLabReport` that NEVER persists directly. `LabPhotoImportSheet` populates an editable table of every extracted row, with a prominent "AI-extracted — verify against your report before saving" banner. Every field is editable; rows can be deleted; new rows can be added. Only the user's confirmed version saves to SwiftData. The save path matches `LabPanelManualSheet` exactly so both flows produce identical model state.

- **Marker trend band shows only when EVERY plotted point has the same numeric range (v2.3a).** `LabMarkerTrendView.consistentRange` returns the shared low/high only when all numeric samples agree; mismatched or absent ranges across panels suppress the band and surface a footer noting why. Picking one range to draw (or averaging) would be interpretation. Per-panel flags still fire on each panel's detail surface from that panel's own range — they're not affected by the trend's band logic.

- **Apple Health clinical-records (FHIR) ingestion was pulled from v2.3a — free dev team can't sign with the `health-records` entitlement.** Documented for the eventual paid-membership rebuild: the entitlement is `com.apple.developer.healthkit.access = ["health-records"]` in `FoodJournal.entitlements`; the privacy string is `NSHealthClinicalHealthRecordsShareUsageDescription` as an `INFOPLIST_KEY_*` in `project.pbxproj`; on paid team Apple ALSO requires "Request Access" → approval per bundle ID before the provisioning profile will issue. When that path becomes available, restore the v2.3a working tree at commit-before-rip-out (will include `ClinicalLabImporter.swift` and `HealthLabImportSheet.swift`) and re-add the LabsView button + sheet. `LabResult.fhirID: String?` is already on the schema as the dedupe primitive for that future ingestion path.

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

- **e1RM is a computed estimate — always label it that way (v2.1b).** In any UI surfacing the Epley-derived value, write "Est." / "Estimated" / "(Epley)" — never bare "1RM." Show the raw underlying sets alongside any estimate so the user can verify the math. Never present e1RM as a lifted weight.

- **Health metric aggregation: steps SUM, rates AVERAGE, sparse LATEST (v2.2).** Steps are cumulative — sum the day. Heart rate / HRV / SpO2 / respiratory rate / wrist temperature / walking double support are RATES; averaging is correct, summing produces meaningless numbers (the classic HK aggregation bug). VO2 max + wrist temp use LATEST because they update infrequently. The aggregation choice lives on the `HealthMetric` descriptor — don't override it inline.

- **HKUnit.percent() returns 0…1, not 0…100 (v2.2).** Calling `quantity.doubleValue(for: HKUnit.percent())` returns a decimal fraction. To display "98%", set the `HealthMetric.displayMultiplier = 100.0` and let the renderer multiply for display. The default for non-percent metrics is `1.0`.

- **HealthKit read-denial is NOT detectable (v1.9 pitfall, reinforced in v2.2).** A denied read type returns no samples — identical to "no data exists." A permanently `–` tile in HealthMetricsView could be either, and the app cannot tell the user which. Do not try to invent denial detection; surface the ambiguity honestly (the v2.2 dashboard footer says so explicitly).

- **USDA HTTP 400 is silently swallowed in the search path (v2.2.1).** api.data.gov's fronting nginx returns 400 Bad Request on certain rapid / bursty request patterns — server-side quirk, not actionable from the client. `SearchSheet.performRemoteSearch` catches `USDAError.http(400, _)` specifically and returns empty USDA results without an error message. **Every other USDA error still surfaces** (missing key, network failure, 401/403/429, decode error) so real problems remain visible. The body of any USDA non-200 response is included in `USDAError.http(_, body)` so when a real error DOES fire, the cause is visible in the UI's error text, not just the status code.

- **OFF text-search is partial-data-by-design (v2.2.1).** Open Food Facts is crowd-sourced and frequently missing optional nutrients — `OpenFoodFactsService.search(_:)` SKIPS products with no name, no nutriments block, or no calorie info (un-loggable junk), but partial products (calories + macros only, every other nutrient nil) ARE included. Nil ≠ 0 is enforced more aggressively here than in USDA: every optional `Double?` nutrient stays nil if OFF doesn't provide it. Do not refactor any OFF parsing path to default missing optionals to 0 — that would silently corrupt the trends layer with fake-zero data points.

## File map (where to look)

- `FoodJournalApp.swift` — entry point, SwiftData container with **16 model types** (7 originals + 7 v2.1a strength/daily + 2 v2.3a labs), owns NotificationCoordinator + registers as UN delegate.
- `Models/Models.swift` — all `@Model` classes: originals (FoodEntry, UserGoals, CachedFood, WaterEntry, CachedPhotoEstimate, LibraryFood, WeightEntry) + v2.1a strength/daily (ExerciseRepEntry, StretchDay, StrengthRoutine, RoutineExercise, StrengthSession, LoggedExercise, LoggedSet — with @Relationship cascades + inverses) + **v2.3a labs (LabPanel cascade-owns LabResult — third nested-cascade pattern in the schema)**. Plus `LibraryFoodUpsert` helper, `FoodFormat` enum, and `LabMarker.normalize(_:)` for testName matching.
- `Services/`
  - `MealTimeHelper.swift` — meal-window config (UserDefaults-backed, configurable in Settings since v1.8); late-night warning logic.
  - `LibraryService.swift` — local library substring search + recency scoring.
  - `USDAService.swift` — USDA FoodData Central text-search (requires personal API key). `USDAError.http(code, body)` carries the response body so api.data.gov's actual complaint is visible in UI errors (v2.2.1).
  - `OpenFoodFactsService.swift` — barcode lookup (v1.5) + text-search (v2.2.1). Search returns `SearchHit` rows matching USDA's normalized shape; partial products with missing optional nutrients are KEPT (nil stays nil), un-loggable products with no name / no nutriments / no calorie info are SKIPPED.
  - `ClaudeVisionService.swift` — photo → nutrition estimate. Multi-image (v1.8.5). v2.2.2: `estimate(images:userContext:apiKey:)` accepts optional typed context that's both prepended to the prompt AND folded into the cache hash (empty context preserves v1.8.5 cache entries verbatim). **v2.3a**: `extractLabReport(image:apiKey:)` AND `extractLabReport(pdfData:apiKey:)` return an `ExtractedLabReport` for the lab photo/PDF path; both go through a shared `performLabExtraction` helper that posts the message + parses + retries. PDF variant uses Claude's `document` content type — multi-page reports go in one shot. Prompt is transcription-only — no interpretation, no unit conversion, no invented ranges; max_tokens 8192 since multi-page lab PDFs list 30+ tests across pages. Output NEVER persists directly; `LabPhotoImportSheet` surfaces it for human review.
  - `KeychainStore.swift` — parameterized key storage (anthropic + usda).
  - `NotificationService.swift` (v1.8.1) — daily meal reminder scheduling.
  - `NotificationCoordinator.swift` (v1.8.1) — `@Observable` UN delegate for foreground display + tap-to-deep-link.
  - `HealthService.swift` (v1.8.2, extended in v1.9 and v2.0) — contains both `HealthService` (low-level HK ops) and `HealthSync` (write orchestration for v1.8.2). Read the file's header comments for the correlation-type gotcha. v1.9 added active/basal energy reads (single-day + range) and `requestEnergyReadAuthorization()`. v2.0 added `WorkoutSummary` (plain struct), `readWorkouts(from:to:)`, `requestWorkoutReadAuthorization()`, and an `activityInfo(for:)` mapping helper for 12+ HKWorkoutActivityType values → (display name, SF Symbol).
  - `UsualSuggestionService.swift` (v1.8.6) — heuristic for "your usual breakfast/lunch/dinner" suggestion banner.
  - `StrengthSchedule.swift` (v2.1b) — pure storage helpers for the `@AppStorage("strengthWeeklySchedule")` JSON map. `decode` / `encode` / `setting` / `weekday(for:)`. Unaware of SwiftData; resolution to a `StrengthRoutine` is the view's job.
  - `HealthMetrics.swift` (v2.2) — `extension HealthService` with the v2.2 descriptor-driven read layer. `HealthMetric` struct + `healthMetrics` list (9 single-value vitals) + generic `readMetricToday` / `readMetricByDay`. Bespoke `SleepNight` + `BPReading` types with their own readers. New `requestHealthMetricsReadAuthorization()` requests all v2.2 read types in one prompt.
  - `LabMarkerAliases.swift` (v2.3a) — `@AppStorage("labMarkerAliases")`-backed JSON `[String: String]` map from `normalizedName → canonical normalizedName`. Encode / decode / cycle-safe `canonical(of:aliases:)` / `merge(canonical:others:into:)`. The lighter alternative to a 17th @Model. Used by `LabMarkerPickerView`, `LabMarkerTrendView`, and `LabMarkerMergeSheet` for non-exact marker grouping.
- `Views/RootView.swift` — TabView root with **5 tabs in v2.2 order**: **Food** (tag 0, was Today — renamed v2.2) · **Workouts** (1) · **Health Data** (2, v2.2) · **Trends** (3) · **Settings** (4). Hoisted `selectedDate` still passes to TodayView (the Food tab). Watches `NotificationCoordinator.pendingMealOpen` for meal-reminder deep-links → tag 0 (Food). The `Add` tab was removed in v2.2; `AddFoodView.swift` stays in the project but is unreferenced.
- `Views/AddFoodView.swift` — **DORMANT as of v2.2.** Was the Add tab's root; removed from the TabView when the tab bar was trimmed to 5 tabs. File is intact and safe to revive if needed. Do not wire it into anything new without confirming with the user — they explicitly chose to remove this surface.
- `Views/WorkoutView.swift` (v2.0, extended in v2.1a / v2.1a.1 / v2.1b) — Workouts tab. Composable section structure: today summary card + Apple Fitness (today inline only, "See previous workouts ›" pushes the rest) + Daily section + **Strength section now contains 6 items in order**: non-tappable Today indicator ("Today: {routine name or Rest}", v2.1b) → Routines → Schedule (v2.1b) → Log a session → History → Trends (v2.1b). Reads `StrengthSchedule.decode(scheduleJSON)` and resolves to `StrengthRoutine` via `allRoutines.first(where:)` (dangling IDs render as Rest). Reads from `HealthService.readWorkouts` on appear + pull-to-refresh. Self-contained state.
- `Views/WorkoutHistoryView.swift` (v2.1a.1) — full-page Apple Fitness history pushed from the Workouts tab. Receives the parent's pre-filtered `previousWorkouts` array (excludes today). Does NOT issue its own HK query — reuses what the parent already fetched. Date-grouped list newest first; "Today" case omitted from `dayLabel` since today is excluded by construction.
- `Views/DailyRepsSheet.swift` (v2.1a) — manages today's individual ExerciseRepEntry bursts for one kind (`pushups` or `situps`). Mirrors WaterEntriesSheet exactly: list, swipe-delete with 5s undo toast, commit on dismiss.
- `Views/RoutinesSheet.swift` (v2.1a) — list + create + edit + delete StrengthRoutine templates. Cascade-deletes their RoutineExercises. Nested `RoutineEditorSheet` for name + ordered exercise list with optional target sets/reps/weight. Uses replace-all on edit (safe — LoggedExercise stores name snapshots).
- `Views/LogSessionSheet.swift` (v2.1a) — log a StrengthSession. Pick routine (or blank); pre-fills exercise list from routine showing target hints (display-only, never copied into stored LoggedSet values). Adds LoggedSets one at a time with auto-incrementing setNumber. Empty exercises skipped on save. Optional durationMinutes field.
- `Views/SessionHistorySheet.swift` (v2.1a) — reverse-chrono list of past StrengthSessions with metadata; tap → read-only SessionDetailView. Swipe-delete with 5s undo at the list level (cascade fires through LoggedExercises → LoggedSets).
- `Views/ScheduleSheet.swift` (v2.1b) — 7 weekday rows (display Mon→Sun; storage Calendar.weekday 1=Sun…7=Sat). Each row is a menu Picker over current routines + Rest. Binding's getter returns nil for dangling stored IDs so dangling routines render as Rest with no crash.
- `Views/StrengthTrendsSheet.swift` (v2.1b) — exercise picker (distinct case-insensitive names, displayed in latest casing). Per-session top-set weight + est. 1RM via Epley, computed INDEPENDENTLY. Swift Charts line+point charts; drawn only when ≥ 2 sessions (single-session shows the data point + "Need 2+ sessions to show a trend." caption). Latest-vs-prior delta row (green up / orange down). Raw sets per session listed below — nil weight/reps surface as "–" in raw but are excluded from math. Empty state when no sessions logged. Filters soft-deleted sessions.
- `Views/HealthMetricsView.swift` (v2.2, extended v2.3a) — the **Health Data tab's** root. LazyVGrid of tiles for sleep + BP specials + 9 generic vital tiles; tapping a tile pushes `MetricTrendView` (generic over `HealthMetric`) or the bespoke `SleepTrendView` / `BPTrendView`. 7d/30d range picker on each trend page. Swift Charts. Missing days are gaps in the chart, never zero values. Footer disclaimer makes the denial-vs-no-data ambiguity explicit. Owns its own NavigationStack since it's a tab destination. **v2.3a**: adds a "Lab results" entry row below the tile grid pushing `LabsView`.
- `Views/LabsView.swift` (v2.3a) — root labs surface pushed from HealthMetricsView. Panel list (reverse-chrono, swipe-delete with 5s undo), two entry points for adding panels (manual / photo), NavigationLink to `LabMarkerPickerView` for trends. Also contains `LabPanelDetailView`, `LabResultRow`, `LabPanelManualSheet`, `LabMarkerPickerView`, `LabMarkerTrendView`, and `LabMarkerMergeSheet`. The neutral in/out-of-range dot lives in `LabResultRow` — only "out of range" language, never "high"/"low"/"elevated"/anything interpretive.
- `Views/LabPhotoImportSheet.swift` (v2.3a) — three entry points (camera photo, Photos pick, `.fileImporter` for PDF) → `ClaudeVisionService.extractLabReport(image:)` or `extractLabReport(pdfData:)` → mandatory editable review screen with "AI-extracted — verify…" banner → save commits only the user's confirmed version. NEVER auto-saves extracted values. Reuses `CameraPicker` from PhotoLogSheet for capture; `PhotosPicker` for gallery picks; PDF picker uses `UTType.pdf` filter. The PDF path is the free-team workaround for the absent v2.3a FHIR ingestion (Apple Health exports panels as PDF directly).
- `Views/TodayView.swift` — date-navigable dashboard. Hosts WaterEntriesSheet (nested) + MealDetailSheet (nested). Smart-suggestion banner (v1.8.6) sits above the daily totals card. v1.9 energy strip (Consumed / Burned / Net / Active) sits between daily totals and water, gated by `showCaloriesBurnedFromHealth`. Meal cards show P/C/F line below calories (v1.8.4). EntryRow recognizes `source == "suggestion"` for sparkles icon. `StatTile.progress` is `Double?`; nil hides the bar (used by Consumed/Burned/Active).
- `Views/AddFoodView.swift` — date-aware add tab + past-day banner + MostUsedSheet (nested).
- `Views/TrendsView.swift` — range picker, per-section averages, Weight section (always visible since v1.8), v1.9 Energy section (Avg Active / Avg Total Burned / Avg Net) shown when `showCaloriesBurnedFromHealth` is on (parallel to Weight, outside the food-data gate), Distribution by meal section (v1.8.4), nested WeightEntriesSheet for log/manage.
- `Views/SearchSheet.swift` — library + **USDA + Open Food Facts (v2.2.1)** unified search. Library swipe-add (v1.7.3) with HealthSync wiring (v1.8.2). USDA + OFF queried concurrently from one debounce; merged + deduped + source-tagged via the `MergedHit` struct. In-flight task cancellation on each keystroke prevents api.data.gov nginx-400 from rapid bursts.
- `Views/NutritionBreakdownSheet.swift` — full 19-nutrient breakdown by selectedDate.
- `Views/BarcodeScannerSheet.swift`, `Views/PhotoLogSheet.swift` — scanner + photo log. PhotoLogSheet was rewritten in v1.8.5 around `images: [UIImage]` for multi-photo. v2.2.2: a `contextField` between the photo strip and the Analyze button accepts optional typed context (weight / brand / prep notes) that's threaded into both the cache lookup and the Claude API call.
- `Views/CSVExportSheet.swift` — exports food/water/weight CSVs (v1.8.2 added weight; v1.9 adds energy.csv when `showCaloriesBurnedFromHealth` is on — per-day active/basal/total/consumed/net columns, nil → empty cell). **v2.2.3**: also writes `strength-sessions.csv` (one row per LoggedSet), `strength-routines.csv` (one row per RoutineExercise; routines exported IN FULL regardless of range), `rep-entries.csv` (pushups/situps bursts), and `stretch-days.csv` (binary). Zero-set exercises and zero-exercise routines are skipped on export.
- `Views/CSVImportSheet.swift` (v2.0.1, extended v2.2.3) — inverse of CSVExportSheet. `.fileImporter` for any subset of food/water/weight/strength-sessions/strength-routines/rep-entries/stretch-days CSVs (header-sniff detection). Per-type empty-table guard (aborts the file's import if non-soft-deleted rows already exist for that type — StrengthRoutine + StretchDay have no soft-delete so any row counts). RFC 4180 parser, POSIX yyyy-MM-dd / HH:mm formatters. Food import calls `LibraryFoodUpsert.upsert`, preserves CSV `source` column, intentionally does NOT fire HealthSync. Strength session import groups flattened rows back into the StrengthSession → LoggedExercise → LoggedSet cascade by (session_date, session_time, routine_name, duration_minutes) → (exercise_name, exercise_order). Strength routine import groups by (routine_name, routine_order, created_at). Nil ≠ 0 enforced for every optional column (weight_lbs, reps, target_sets, target_reps, target_weight_lbs, duration_minutes, routine_name).
- `Views/NutrientGoalsSheet.swift` — editable goals for the 14 secondary nutrients.
- `Views/AuxViews.swift` — ConfirmFoodView, ManualEntrySheet, EditEntrySheet, SettingsView (Meal time schedule, Reminders, Smart suggestions, Apple Health sections; Data section has Export + **Import (v2.0.1)** + Reset library), AnthropicKeySheet, USDAKeySheet, RelogSheet (dormant), dismissKeyboard, SelectAllOnFocus modifier, Haptic helper. Large file (~70KB) — search by `struct` keyword to navigate.

## Manual Xcode steps locked in (don't repeat in new sessions)

- **HealthKit capability** is enabled (Signing & Capabilities → HealthKit). `FoodJournal.entitlements` contains `com.apple.developer.healthkit = true`.
- `com.apple.developer.healthkit.access = ["health-records"]` was added during v2.3a development then PULLED — free dev team can't sign with it. Re-add only after paid Developer Program enrollment + per-bundle-ID "Request Access" approval from Apple.
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
