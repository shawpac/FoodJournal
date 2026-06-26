# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v2.2.1. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Recently shipped

### v2.2.1 — Open Food Facts text search alongside USDA (merged, deduped, source-tagged)

**Fixes USDA's thin branded/packaged coverage by adding OFF as a second text-search source. USDA stays — this ADDS a source, doesn't replace one.**

- ✅ New `OpenFoodFactsService.SearchHit` + `search(_:)` text-search method using OFF's classic search endpoint. No API key. Returns up to ~25 usable products; malformed entries (no name / no nutriments / no calorie info) are SKIPPED rather than included with fake zeros.
- ✅ Nutrient parsing mirrors the existing barcode-path conversions exactly: macros in g; minerals (sodium / potassium / cholesterol / calcium / iron / magnesium) in mg; vitamins A & D in µg; vitamin C in mg. Salt → sodium fallback preserved.
- ✅ SearchSheet now fires USDA + OFF **concurrently** behind a single 300ms debounce. One failing source does NOT block the other — partial coverage beats no coverage.
- ✅ Results merge into ONE ranked list with per-row source tags (`USDA` green / `OFF` orange). Cross-source dedupe collapses near-duplicates on name + brand + ±15% calorie tolerance, **preferring USDA on collisions** (lab-quality data wins over crowd-sourced).
- ✅ Relevance scorer + dedupe heuristic are intentionally readable and tunable. The first-pass thresholds may over- or under-collapse on some queries; comments document where to adjust.
- ✅ "Include branded foods" toggle now gates USDA Branded AND all OFF results (OFF is overwhelmingly branded). Off → USDA generic only. On → USDA generic + USDA Branded + OFF.
- ✅ In-flight remote-fetch task is explicitly cancelled on each keystroke (`@State remoteFetchTask`). Prevents rapid typing from piling concurrent HTTPS requests onto the same HTTP/2 connection — fixes a nginx-400 symptom that appeared when two-source concurrency stressed api.data.gov's load balancer.
- ✅ USDA HTTP 400 is silently swallowed (server-side quirk, not actionable). Every other USDA error (missing key, 401/403/429, network failure, decode) still surfaces with the actual cause text from api.data.gov's response body — `USDAError.http(code, body)` now carries the body so the UI's error text is informative.
- ✅ Defensive whitespace trim on the USDA API key inside `USDAService.search` so a stray trailing newline pasted from email no longer triggers a 403.
- ✅ Schema-clean. View + service changes only.

### v2.2 — Health Data tab (read-only Apple Health metrics) + tab bar reorg

**Closes the read-side Apple Health loop: vitals + sleep + BP are now a first-class surface, not buried behind a row. Also trims the tab bar to a sane 5 tabs.**

- ✅ New **Health Data tab** (3rd of 5), pushing a read-only dashboard. SF Symbol `heart.text.square`.
- ✅ Tile grid: sleep tile (last night's asleep duration + REM/Core/Deep stage pills), BP tile (latest pair or `–` with a "manual entry or cuff" hint), plus 9 single-value vitals — Heart rate, Resting HR, HRV, Blood oxygen, Respiratory rate, Steps, VO2 max, Wrist temperature, Walking double support.
- ✅ Each tile is tappable and pushes a 7d / 30d Swift Charts trend page. **Missing days are gaps, not zero values** (nil ≠ 0). Average / Min / Max / Days-with-data underneath.
- ✅ Sleep trend plots nightly asleep duration in hours. BP trend plots systolic + diastolic as two color-coded series.
- ✅ **Architecture is descriptor-driven.** `HealthService.healthMetrics: [HealthMetric]` is the single source of truth — adding a new vital is a one-line entry. Generic `readMetricToday` / `readMetricByDay` dispatch on `MetricAggregation` (`.average` for rate-style metrics; `.sum` for steps; `.latest` for VO2 max + wrist temp). Sleep + BP have bespoke readers because they don't fit the single-value pattern. New `requestHealthMetricsReadAuthorization()` requests all v2.2 read types in one prompt.
- ✅ Reuses the existing `NSHealthShareUsageDescription` privacy string from v1.8.2. No new Info.plist entry.
- ✅ Honest "denial = no data" disclaimer at the bottom: HealthKit can't expose read-grant status, so a permanently `–` tile could be no data OR denied permission.
- ✅ **Tab bar reorg** (the user-driven companion change). New order: `Food · Workouts · Health Data · Trends · Settings` — 5 tabs, no More overflow. **Today renamed to Food.** **Add tab removed** (food is logged via the Food tab's meal cards). The notification deep-link still targets tag 0 (= Food = the same TodayView surface). `AddFoodView.swift` is kept in the project but unreferenced; safe to delete later.
- ✅ Schema-clean. No new @Model, no FoodJournalApp.swift change. HealthKit data is read on demand, never cached locally — same invariant as v1.9 energy and v2.0 workouts.

### v2.1b — Weekly strength schedule + per-exercise trends

**Closes out the v2.1 strength feature set. Schedule tells you what to do today; trends show whether the work is paying off. Schema-clean — built entirely on the v2.1a model layer.**

- ✅ New `Schedule` entry point in the Workouts tab's Strength section. 7-row sheet (Mon → Sun display order; storage uses Calendar.weekday 1=Sun…7=Sat). Each row is a menu Picker over the current routines + Rest.
- ✅ Non-tappable "Today: {routine name or Rest}" indicator at the top of the Strength section card reflects the current weekday's pick. Updates instantly via `@AppStorage`.
- ✅ `Log a session` pre-selects today's scheduled routine on `onAppear` when one resolves — manual override still works.
- ✅ **Robustness**: if a stored routine UUID no longer resolves (the user deleted that routine), the day silently falls back to Rest. No crash, no dangling name surfaced. The Binding's getter handles the unresolved case.
- ✅ Storage: single `@AppStorage("strengthWeeklySchedule")` JSON string encoding a `[weekday-int-as-string: routineID-uuid-string]` map. New `Services/StrengthSchedule.swift` holds the pure encode/decode/setting/weekday helpers; resolution to a SwiftData `StrengthRoutine` happens at view time.
- ✅ New `Trends` entry point in the Strength section → `StrengthTrendsSheet`. Pick an exercise from a menu of every distinct name across all your non-soft-deleted sessions (case-insensitive dedupe, latest casing).
- ✅ Two per-session metrics, computed **independently** (the top-weight set and the top-e1RM set in the same session may be different sets):
  - **Top-set weight**: max non-nil `weightLbs` across the exercise's sets in that session.
  - **Estimated 1RM** via Epley `weight × (1 + reps/30)`, max over sets with BOTH non-nil weight AND non-nil reps. Always labeled "Est." / "(Epley)" — never bare 1RM.
- ✅ Two line+point charts (Swift Charts, iOS 16+, project targets iOS 18+). Drawn only when ≥ 2 sessions exist; a single session shows the data point with a "Need 2+ sessions to show a trend." caption — no fake line.
- ✅ Latest-vs-prior delta rows (green ↑ when up, orange ↓ when down, "–" when no prior session).
- ✅ Raw sets per session listed below the charts so the actual logged data is never hidden behind the estimate. Sets with nil weight or reps surface raw (`135 × –`) but are excluded from the trend math.
- ✅ Strength section grew to 6 items: Today indicator → Routines → Schedule → Log a session → History → Trends.
- ✅ Schema-clean. No new @Model, no FoodJournalApp.swift change.

### v2.1a.1 — Apple Fitness split into inline-today + history page

**The Workouts tab was too tall: a 30-day Apple Fitness list pushed the daily-use controls (pushups / situps / stretch, strength) far down. Split fixes the scroll problem.**

- ✅ Apple Fitness section on the Workouts tab now shows ONLY today's workouts inline, with the same row styling as before.
- ✅ Below today's rows: a new "See previous workouts ›" navigation row pushes a new `WorkoutHistoryView` page listing the rest of the last 30 days grouped by day, newest first. The page omits "Today" headers by construction.
- ✅ Empty-state UX preserved with a finer breakdown: "No workouts logged today." inline when today is empty but earlier days have data; the original full "No workouts found" card only when the entire 30-day window is empty (and the "See previous workouts" row is hidden).
- ✅ No new HealthKit query and no new auth — `WorkoutHistoryView` receives the parent's pre-filtered `previousWorkouts` array. Matches the v1.9 invariant: HK data is read on demand, never cached locally; the parent owns the fetch.
- ✅ Cleaned up the now-dead `groupedWorkouts` / `dayHeader` / `DayGroup` helpers from `WorkoutView` — they were specific to the old multi-day inline list and the equivalents now live in `WorkoutHistoryView` where they apply.
- ✅ Schema-clean. View reorganization only — no models, no FoodJournalApp.swift change.

### v2.1a — Strength routines + sessions + daily reps tracker (schema change)

**The first non-food fitness logging surface. 7 new @Models — the schema's first @Relationship cascades. The v2.0.1 CSV import did its job: the reinstall round-trip recovered every food/water/weight row.**

- ✅ 7 new `@Model` types in `Models/Models.swift`: `ExerciseRepEntry`, `StretchDay`, `StrengthRoutine`, `RoutineExercise`, `StrengthSession`, `LoggedExercise`, `LoggedSet`. SwiftData container now holds 14 model types total.
- ✅ First @Relationship cascades in the project — two-level nested on the strength side: `StrengthSession → LoggedExercise → LoggedSet`, with both relationship lines declaring `inverse:` on the parent side and the child carrying the back-pointer.
- ✅ `LoggedExercise` stores the exercise NAME as a String snapshot, NOT a relationship to RoutineExercise. Editing or deleting a routine doesn't retroactively change session history. Targets are display-only hints during logging — never copied into stored LoggedSet values.
- ✅ Workouts tab extended with two new sections (composable structure preserved from v2.0):
  - **Daily**: pushup/situp append cards with running sum, custom-count field, Log button; long-press the count → individual-burst manager (DailyRepsSheet) with swipe-delete + 5s undo (mirrors WaterEntriesSheet exactly). Stretched-today binary toggle creates-or-toggles the day's StretchDay row.
  - **Strength**: nav rows for Routines (list + create + edit + delete templates), Log a session (pick routine or blank, pre-fill exercises with target hints, add sets one at a time), History (reverse-chrono list + read-only SessionDetailView, cascade-safe soft-delete with 5s undo).
- ✅ **NO HealthKit writes from any of these models.** Strength has no HK schema, and the user's Apple Watch already captures calorie burn passively — writing strength workouts would double-count against Today's energy strip. Daily-tracker data has no HK type either. All v2.1a data is in-app only by design.
- ✅ Schema change → reinstall. Tested via the v2.0.1 CSV export/reinstall/import round-trip with green Imported-N results for food/water/weight and round-trip nil-not-zero verified.

### v2.0.1 — CSV import (de-risks future schema-change reinstalls)

**The inverse of CSVExportSheet: restore food/water/weight history into a freshly reinstalled app.**

- ✅ New `CSVImportSheet` reachable from Settings → Data → Import data. `.fileImporter` accepts any subset of food/water/weight CSVs; kind is detected by header sniff, not filename, so renamed files still work.
- ✅ APPEND-ONLY with a per-type empty-table guard. Each of FoodEntry/WaterEntry/WeightEntry must be empty (no non-soft-deleted rows) before that file's import will run. Non-empty tables get an orange "already contains data — import skipped" message; zero rows are touched. No dedupe/merge logic — by design, since the contract is "import only into a fresh install."
- ✅ Exact inverse of CSVExportSheet: same files, same column order, same `yyyy-MM-dd` / `HH:mm` POSIX formatters, same RFC 4180 quoting. Critical nil ≠ 0 invariant preserved: empty optional cells parse to `Double? = nil`, never 0. Empty required fields (name, loggedAt, servings, calories, protein/carbs/fat, amountOz, weightLbs) mark the row malformed and skip it.
- ✅ Exporter writes nutrient TOTALS (per-serving × servings); importer divides back by servings to recover per-serving storage. `servings ≤ 0` is treated as malformed (avoids divide-by-zero).
- ✅ Imported FoodEntry calls `LibraryFoodUpsert.upsert(from:in:)` like every other save path so the search library + useCount rebuilds.
- ✅ Imported entries intentionally do NOT fire HealthSync — they're historical restorations, not new logs; re-writing to Health would duplicate or orphan samples.
- ✅ Source provenance preserved per-row: the FoodEntry's `source` is read from the CSV's source column (index 5). Only a blank cell falls back to `"import"`. Keeps `EntryRow.iconForSource` mapping intact across reinstalls (e.g. `source == "suggestion"` still renders with sparkles).
- ✅ Energy CSV is recognized and reported as "not stored locally — Health is the source of truth."
- ✅ Schema-clean. No new @Model fields, no reinstall.

### v2.0 — Workouts tab + display-name rename to "MS Fitness"

**App name on the home screen now reflects the broader fitness scope. Workouts tab reads from Apple Health.**

- ✅ Display name: `INFOPLIST_KEY_CFBundleDisplayName = "MS Fitness"` in both Debug and Release configs. Bundle ID (`com.shawbler.FoodJournal`), `PRODUCT_NAME`, Xcode project name, and repo all remain "FoodJournal" — changing the bundle ID would orphan the SwiftData store.
- ✅ New `WorkoutView` registered as the 5th tab in RootView (tag 3, between Trends and Settings; Settings shifts to tag 4). SF Symbol `figure.run`. Notification deep-link still targets tag 0 (Today).
- ✅ HealthService extended: new `WorkoutSummary` plain struct (NOT a @Model — keeps schema clean), `readWorkouts(from:to:)` querying HKWorkout via `HKSampleQueryDescriptor`, `requestWorkoutReadAuthorization()` for the standalone read prompt, `activityInfo(for:)` mapping 12+ HKWorkoutActivityType values to (display name, SF Symbol) with a sensible default.
- ✅ Active calories use `workout.statistics(for: .activeEnergyBurned)` (modern API; deprecated `workout.totalEnergyBurned` is NOT used). Distance maps `running/walking/hiking → distanceWalkingRunning` and `cycling → distanceCycling`; everything else is nil. Nil ≠ 0 applies — a strength workout shows no distance line.
- ✅ Today summary card: 3 stat tiles (Workouts count today / Active cal today / Total duration today). "—" everywhere when no data (nil ≠ 0).
- ✅ Apple Fitness list section: last 30 days, newest first, grouped by day with Today / Yesterday / formatted-date headers. Pull-to-refresh re-queries.
- ✅ Composable section structure intentionally leaves slots open for v2.1 expansions (daily bodyweight tracker, strength routines) without re-architecting.
- ✅ Empty state phrased "No workouts found" — HealthKit hides read-grant status for privacy, so genuine-no-data and denied-permission can't be distinguished by the app.
- ✅ Schema-clean. No reinstall.

### v1.9 — Calories burned from Apple Health (read-only)

**Closes the loop on Apple Health: writes were v1.8.2, reads land here. Net calories now visible everywhere it matters.**

- ✅ New HealthService energy reads: `readActiveEnergy(on:)`, `readBasalEnergy(on:)`, `readEnergySummary(on:)` (parallel fetch), plus range variants `readActiveEnergy(from:to:)` and `readBasalEnergy(from:to:)` returning `[Date: Double]` dicts keyed by start-of-day. Active and basal energy added to the HealthKit READ types only — read-only by design.
- ✅ New `requestEnergyReadAuthorization()` prompts only for the energy types, used by the standalone toggle.
- ✅ New Settings → Apple Health → "Show calories burned" toggle, independent from the existing "Sync to Apple Health" master toggle. Two toggles, two flows, two purposes.
- ✅ Today: a second 4-tile strip appears below the daily totals card — Consumed / Burned / Net / Active. Net shows a progress bar against the configurable Net calories goal; the other three are bare tiles. Re-fetches on selectedDate change so past-day navigation works.
- ✅ Trends: new Energy section (parallel to Weight, outside the food-data gate) — Avg Active, Avg Total Burned, Avg Net. Avg Net only counts days with BOTH consumed and burn data. Days with no burn samples are excluded from all three averages (nil ≠ 0).
- ✅ Net calories goal stored via `@AppStorage("netCaloriesGoal")` with sentinel-0 fallback: 0 = "track the daily calorie goal automatically." Computed binding in Settings, computed property in TodayView. No schema change to `UserGoals`.
- ✅ CSV export adds a 4th file (energy.csv) when toggle is on — date, activeEnergyKcal, basalEnergyKcal, totalBurnedKcal, consumedKcal, netCaloriesKcal. One row per day with any non-nil data. Nil cells empty.
- ✅ `StatTile.progress` is now `Double?`; nil hides the bar. Existing 4 main-card tiles still pass non-optional Doubles (Swift wraps implicitly).
- ✅ Schema-clean. No reinstall.

### v1.8.6 — Smart "your usual?" suggestions

**The "logging the same breakfast every day is N taps too many" friction, gone.**

- ✅ New `UsualSuggestionService` — heuristic: most-frequently-logged food for a meal slot over the last 14 days, threshold ≥ 3 occurrences. Snacks excluded (too unpredictable).
- ✅ Orange banner on Today above the daily-totals card. Surfaces only during a meal's configured window (breakfast/lunch/dinner) + 1h grace past the end.
- ✅ Tap = one-tap log with 5-second undo. Mirrors template entry's nutrients + servings + unit. Source field set to `"suggestion"` (sparkles icon on meal cards).
- ✅ X dismisses for the rest of today (in-memory). Logging anything else in that meal also hides it (the trigger gate flips).
- ✅ Settings → Smart suggestions toggle. Defaults ON.
- ✅ No schema change. Effect grows with usage history.

### v1.8.5 — Better photo logging: multi-photo + low-confidence retry

**Sometimes one angle isn't enough; sometimes Claude is unsure.**

- ✅ `ClaudeVisionService.estimate(images:apiKey:)` sends N image blocks in a single API call (max 3 in UI). Single-photo wrapper kept for back-compat.
- ✅ `prepareImages(_:)` computes a stable, order-independent combined cache hash. Single-photo case unchanged so existing cache entries still hit.
- ✅ Updated multi-photo prompt tells Claude the photos show the SAME meal from different angles, refining one estimate.
- ✅ PhotoLogSheet restructured around `images: [UIImage]` (max 3). Horizontal thumbnail strip + X overlay per thumb + inline "+ Add angle" tile.
- ✅ Low-confidence card surfaces above EstimateCard when Claude returns `"low"`. Two actions: Add angle (re-opens camera), Re-analyze (cache-bypassing API call; upserts the existing cache row).
- ✅ No schema change.

### v1.8.4 — Macros breakdown by meal

**Answer the "I keep eating 80% of my carbs at dinner" question.**

- ✅ Today meal cards show a second line below the calorie count: `P 18g · C 42g · F 12g`. Empty cards stay clean.
- ✅ TrendsView gains "Distribution by meal" section between Macros and Water. Four rows (Breakfast / Lunch / Dinner / Snacks) each with four chips: `Cal X% · P X% · C X% · F X%`.
- ✅ No schema change. Hidden alongside the Macros section when the range is empty.

### v1.8.3 — Editable time-of-day on past-day entries

**Resolves the "every past-day entry shows 12:00 PM" cosmetic gap.**

- ✅ ConfirmFoodView / ManualEntrySheet / PhotoLogSheet each show a "Time logged" picker only when logging to a past day. Initialized to noon (legacy default).
- ✅ EditEntrySheet's "When" section gains a Time picker alongside the existing Date picker — both bind to `loggedAt` with different displayedComponents so each only edits its own field.
- ✅ SearchSheet quick-add intentionally skipped to preserve the one-gesture promise.
- ✅ WaterEntriesSheet skipped — water totals don't depend on time-of-day.

### v1.8.2 — Apple Health two-way sync

**Calorie totals, macros, water, and weight mirrored to the Health app. Weight imports both ways.**

- ✅ Schema change: `healthSampleID` on FoodEntry/WaterEntry/WeightEntry, `importedFromHealth` on WeightEntry.
- ✅ HealthKit capability + privacy strings (NSHealthShareUsageDescription / NSHealthUpdateUsageDescription).
- ✅ New `HealthService`: per-type auth, write/delete/read primitives. Food saved as individual quantity samples (NOT HKCorrelation — correlation types can't be authorized, which makes them undeletable). Critical lesson baked into the service file's header comments.
- ✅ New `HealthSync`: orchestration above HealthService. Writes gated by master toggle; deletes always attempt when entry has `healthSampleID`. EditEntrySheet path: delete old + write new.
- ✅ Wired into every save path (Confirm / Manual / Photo / SearchSheet quick-add / RelogSheet / EditEntrySheet / water log / weight log).
- ✅ Wired into every commit-delete path (TodayView food, WaterEntriesSheet, WeightEntriesSheet).
- ✅ Settings → Apple Health → master toggle + "Import weight from Apple Health" button (dedupes by healthSampleID).
- ✅ CSV export adds a third file: weight.csv.
- ✅ Weight delete-sync skips entries with `importedFromHealth = true` so in-app deletes don't remove the user's smart-scale source data.

### v1.8.1 — Daily meal reminders (local notifications)

**Off-app nudge to log each meal at the configured time.**

- ✅ New `NotificationService`: schedule / cancel / authorizationStatus. Daily-repeating `UNCalendarNotificationTrigger`. Stable identifier per meal so toggle ON/OFF + time changes replace cleanly.
- ✅ New `@MainActor @Observable NotificationCoordinator`: UN delegate. Foreground notifications still show a banner (default iOS behavior swallows them). Tap → `pendingMealOpen = mealType`.
- ✅ FoodJournalApp owns the coordinator, registers as the UN delegate, injects via `.environment`.
- ✅ RootView watches `pendingMealOpen`, switches to Today tab, resets selectedDate, threads `pendingMealKey` into TodayView. TodayView opens that meal's MealDetailSheet.
- ✅ Settings → Reminders: toggle + time picker per meal (Breakfast / Lunch / Dinner). All defaults off.
- ✅ Permission flow: first toggle ON triggers the iOS prompt; denial reverts the toggle and surfaces an alert with Open Settings deep link.

### v1.8 — Water undo + weight tracking + custom meal-time schedules

**The v1.8 schema-change bundle: three Tier-1 items, one reinstall.**

- ✅ `WaterEntry.pendingDeleteAt: Date?` schema field. WaterEntriesSheet swipe-delete now soft-deletes with 5-second undo toast.
- ✅ New `WeightEntry` `@Model` (weightLbs, loggedAt, pendingDeleteAt). Registered in SwiftData container.
- ✅ Trends gains a Weight section (always visible — independent of food/water data): Latest / Avg in range / Change in range (green ↓ / orange ↑). NavigationLink → `WeightEntriesSheet` for logging + managing entries with swipe-delete + 5-second undo.
- ✅ `MealTimeHelper` reads breakfast/lunch/dinner start+end hours from UserDefaults. Refactored `mealType()` to use configured windows with breakfast > lunch > dinner precedence; falls through to "snack." `isLateNight()` shares the same `hourInWindow` helper, correctly handles wrap-around for any window.
- ✅ Settings → Meal time schedule: 3 picker rows + "Reset to defaults."
- ✅ Schema change → reinstall required (CSV export first).

### v1.7.4 — Edit entry date picker
- ✅ EditEntrySheet "When" section with `DatePicker(displayedComponents: .date)` to fix any misdated entry. Time component preserved automatically.

### v1.7.3 — SearchSheet library swipe-add
- ✅ Leading-edge swipe on library rows → green Quick add. One-gesture log, 5-second undo.

### v1.7.2 — Add tab inherits Today's selectedDate
- ✅ `selectedDate` hoisted to RootView, `@Binding` to both Today and Add. Past-day banner with Today reset button. Dynamic nav title. Bug fix bundled: ConfirmFoodView's missing defaultDate mutation.

### v1.7.1 — Date-navigable Today + past-day logging
- ✅ Toolbar chevrons + tap-the-title date picker. All cards reflect selectedDate. defaultDate threaded through all add flows. MealDetailSheet + NutritionBreakdownSheet accept selectedDate.

### v1.7 — Trends + Most Used undo + totals-mode entry + configurable late-night
- ✅ Trends 4th tab with range selector + daily averages + "based on N of M days" caption.
- ✅ Most Used swipe-remove with undo.
- ✅ Manual entry per-serving / totals-mode segmented picker.
- ✅ Late-night warning toggle + time pickers.

### v1.6 — Today redesign + meal context everywhere
- ✅ Always-visible meal cards + MealDetailSheet. Most Used replaces Recents. defaultMeal threaded everywhere. Time-derived meal defaults + late-night confirmation.

### v1.5 — Search + library + cleaner Settings + identity
- ✅ LibraryFood model + passive upsert. LibraryService + USDAService. Unified SearchSheet. CSV export. Reset library button. Custom app icon.

### v1.4 — Cost-down on photo logging
- ✅ Sonnet (not Opus), confirmation step, image-hash cache, camera-based capture, swipe-delete with undo.

### v1.3
- ✅ "Calories" instead of "kcal," click-to-edit logged entries, serving unit dropdown, better Recents, meal grouping on Today, select-all-on-focus.

---

## What's left

### Tier 2 — deferred until publish decision

**iCloud / CloudKit sync across devices**

Convert SwiftData container to use CloudKit. Data syncs to other Apple devices automatically.

⚠️ **Requires the paid Apple Developer Program ($99/year).** Free Apple ID accounts cannot enable iCloud capability. Confirmed — the iCloud capability doesn't appear in Xcode's picker on a free team. (HealthKit DOES work — that's a separate entitlement.)

⚠️ **Major schema audit:** every property on every `@Model` class must become optional or have a default value. Final reset is required, after which proper lightweight migrations replace the delete-and-reinstall workflow.

Worth doing only if Mike (a) actually starts using a second Apple device, or (b) decides to pursue App Store release (which the $99 also unlocks). Until then, deferred.

---

### Tier 3 — polish & new capabilities

**Recipe support**

"I made stir-fry with chicken, rice, broccoli, soy sauce." Save the combination as a named recipe so you can log it as one item next time. Simplest model: a recipe is just a saved meal of multiple FoodEntry rows that get inserted together. ~1.5h.

⚠️ Schema change required (new `@Model` class). Could bundle into a future schema session if other items pile up.

**Real OCR of nutrition labels**

Photo of nutrition facts panel → parsed into a CachedFood entry. ClaudeVisionService can already do this with a different prompt and UI route. Fills the Open Food Facts gap for unbranded / private-label products. No schema change. ~30 min.

**EditEntrySheet totals mode (deferred from v1.7)**

The Manual entry totals toggle is per-serving-only on the edit side. Adding totals editing is doable but tricky — the existing entry is already in per-serving form, and re-deriving on every keystroke gets confusing. Defer until/unless it actually bites. (Date AND time editing IS supported as of v1.8.3.)

**UI polish across the board**
- Animated number transitions (stat tiles smoothly counting up).
- Better empty states with illustrations.
- Dark mode tuning.
- Custom typography — currently very system-default.
- Tinted variant of the app icon for iOS appearance modes.
- Clean up the wonky indentation in BarcodeScannerSheet's ConfirmFoodView call (cosmetic only).

**Public release**

Paid Apple Developer account ($99/year), App Store Connect setup, screenshots, privacy policy, marketing site. Also requires: replacing the AI-generated devil-fruit icon with original art. A few-day project on its own. The code is structured well enough that this isn't a big lift technically — the work is in the surrounding artifacts.

---

## What I'd do next

The app is in a great place at v2.2.1. **The v2.1 strength feature set is fully done**, **v2.2 closed the read-side Apple Health loop**, and **v2.2.1 fixed USDA's thin packaged-food coverage by adding Open Food Facts as a second text-search source.** Tier 1 + Tier 2 (minus iCloud) are fully shipped; v1.9 closed the Apple Health write loop; v2.0 added Workouts and renamed the app; v2.0.1 unblocks schema-change reinstalls via CSV import; v2.1a–b added the full strength + daily-tracker surface; v2.2 added vitals + sleep + BP and consolidated the tab bar to 5 tabs; v2.2.1 added OFF text search with merge + dedupe + source tags. The daily-driver loop is genuinely tight:
- Logging is one tap (Most Used / suggestion banner / SearchSheet swipe-add) or a guided flow.
- Past-day support works end-to-end with proper time fidelity.
- Editing is fully flexible — every field, date, time, plus delete-with-undo.
- Trends shows longitudinal weight, macros, distribution by meal, per-nutrient averages, and energy.
- Apple Health mirrors food/water/weight TO Health and reads workouts + energy FROM Health; reminders nudge from outside the app.
- Reinstalls are no longer lossy — export then import.
- Strength + daily reps + stretch tracking are logged and persisted (verified across force-quit and a full reinstall round-trip).
- Strength routines have a weekly schedule that drives a Today indicator and pre-selects the right routine when you log a session.
- Per-exercise trends show top weight + est. 1RM with honest empty/sparse states and raw-sets disclosure.
- Vitals + sleep + BP are visible as a first-class tab with honest gaps for missing data.

The Health-data layer is now FLOWING — every datapoint the v2.4 dashboard / rating idea would summarize is queryable. v2.3 (medical import / lab data) is still the cleanest non-Tier-3 candidate before v2.4 if you go that route. What's left otherwise is all Tier 3 — nothing blocking the daily-driver loop. Pick when motivated:

1. **Recipe support** — single new `@Model` for a saved meal of multiple FoodEntry rows. Bundle with the next schema window if more items accumulate.

2. **OCR of nutrition labels** — quick Claude-vision reuse. Fills the Open Food Facts gap for unbranded products. No schema change.

3. **UI polish** — tinted app icon variant for iOS appearance modes, animated number transitions, dark-mode tuning.

4. **CloudKit + App Store** — gated on the $99 decision. Still deferred.

Possible v2.1c-style follow-ups if real usage exposes a gap (not committed):
- **Per-session total volume trends** (sum of weight × reps) — was intentionally left out of v2.1b; cheap to add if Mike wants the third metric alongside top-set + e1RM.
- **Strength workout writes to Apple Health** — currently OFF by design (Watch already captures calories, double-counting risk). Could revisit if a strength-specific HK schema becomes meaningful.
