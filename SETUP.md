# FoodJournal (display name: "MS Fitness")

A personal iOS nutrition + fitness tracker. Display name on the home screen is **"MS Fitness"** as of v2.0; bundle ID, Xcode project name, and repo all still say "FoodJournal." Native SwiftUI + SwiftData, runs entirely on-device except for external calls (Open Food Facts for barcode lookups + text search, Anthropic Claude for photo estimation, USDA FoodData Central for food name search) and an optional two-way Apple Health sync.

**Tab bar (5 tabs since v2.2):** `Food · Workouts · Health Data · Trends · Settings`. The Add tab was removed in v2.2 — food is added via the Food tab's meal cards (which open MealDetailSheet with Search / Scan / Photo / Manual entry buttons).

Built collaboratively across multiple sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v2.3a)

**Working features**

*Today tab — date-navigable meal-card dashboard*
- **Date navigation in the toolbar:** chevron `‹` / `›` step the view backward and forward by day. The forward chevron is disabled when viewing today. The center title shows "Today," "Yesterday," or a formatted date like "Mon, May 4."
- **Tap the title** → opens a date-picker sheet with a graphical calendar. Future dates are visually disabled. A **Today** button jumps you back.
- **All cards reflect the selected day:** daily totals, water tracking, meal-card subtotals, and Full breakdown.
- **Daily totals card:** four equally-sized horizontal stat tiles (Calories / Protein / Carbs / Fat) with progress bars against your daily goal.
- **Water tracking card:** progress bar, custom-amount entry with Log (negatives supported), tap the count to set total directly, long-press the count to see and delete individual water entries. Logging water on a past day uses the picker time if set, else noon.
- **Energy strip (v1.9):** a second row of 4 stat tiles below the daily totals — Consumed (from FoodEntry) / Burned (Active + Basal from Apple Health) / Net (Consumed − Burned, can go negative) / Active (Active Energy only from Health). The Net tile shows a progress bar against the configurable Net calories goal. Tiles display "—" when burn data is unavailable. Hidden when "Show calories burned" is off in Settings.
- **Meal-card dashboard:** four cards always visible — Breakfast, Lunch, Dinner, Snack. Each shows the per-meal calorie subtotal AND a P/C/F gram subtitle (v1.8.4) below. Empty meals are ghosted with `—`.
- **Tap any meal card → MealDetailSheet:** focused sheet for that meal with totals, all entries listed, swipe-left to soft-delete (with 5-second undo), tap any entry to edit all fields plus date AND time (v1.8.3), and a four-button "+ Add to {meal}" section. Picking an entry point pre-tags meal context AND selected date.
- **"Your usual breakfast?" banner (v1.8.6):** orange-tinted banner above the daily totals card. Appears during a meal's time window (with 1h grace) when you've logged the same food for that meal ≥ 3 times in the last 14 days. Tap = one-tap log with 5-second undo. X to dismiss for the rest of today. Opt out in Settings.
- **"Full breakdown ›"** → modal sheet showing all 19 nutrients in five sections with progress bars, respecting selectedDate and excluding soft-deleted entries.

*Add tab — Most Used + Search + 3 inputs (date-aware)*
- **Inherits Today's selectedDate.** Logging from Add while on a past day creates entries on that day.
- **Past-day banner** appears at the top when not on today: orange card with a **Today** reset button.
- **Dynamic nav title:** "Add food" today, "Add to Yesterday" / "Add to Mon, May 4" otherwise.
- **Most Used** card → MostUsedSheet listing top 10 library foods by hybrid score (`useCount + recency * 5`). Tap row → Confirm screen. Swipe-left removes from library with 5-second undo.
- **Search foods (v2.2.1: USDA + Open Food Facts)** — unified search across the local library, USDA FoodData Central, and Open Food Facts (text search, no API key). Library streams instantly; USDA + OFF run **concurrently** behind a single 300ms debounce. Results merge into one ranked list with per-row source tags (green USDA / orange OFF). Cross-source dedupe collapses near-duplicates on name + brand + ±15% calorie tolerance, preferring USDA on collisions. **Branded toggle** gates both USDA Branded and OFF (OFF is almost entirely branded). One failing source doesn't block the other — partial coverage beats none. In-flight task cancellation on each keystroke; USDA HTTP 400 is silently swallowed (server-side quirk) while every other USDA error still surfaces.
- **Library swipe-add (v1.7.3)** — swipe right on any library row → green **Quick add** button creates a FoodEntry directly with default amounts (100g for per-100g foods, 1 serving otherwise). 5-second undo. Late-night warning still fires for snacks.
- **Scan barcode** — Open Food Facts lookup pulls 19 nutrients where available.
- **Photo estimate (v1.8.5: multi-photo; v2.2.2: typed context)** — opens the camera. After capture you see a thumbnail strip; up to 3 photos for the same meal from different angles. X to remove a thumb. **Optional context field below the photo strip** lets you type weights, brands, prep notes (e.g. "6 oz grilled chicken, no oil") that Claude is instructed to treat as authoritative over what it would infer from the photo alone. Analyze sends photos + context to Claude. Low-confidence card with Re-analyze (cache-bypassing) + Add angle. Context is folded into the cache hash so the same photo with different context misses cache; an empty context preserves the v1.8.5 cache hash byte-for-byte.
- **Manual entry** — full form with Carbs detail / Fats detail / Cholesterol & electrolytes / Vitamins & minerals sections. Serving unit picker (g, ml, oz, serving, cup, tbsp, tsp, plus Custom…). Per-serving / total amount toggle.

*Manual entry per-serving / totals mode*
- Segmented picker at the top of Serving: "Per serving" / "Total amount." Per serving is default (legacy).
- Totals mode: "Servings" → "Amount," macros header → "Macros (totals)." On save, totals divide by amount → per-serving stored. Storage layer unchanged.

*Time-of-day on past-day entries (v1.8.3)*
- ConfirmFoodView / ManualEntrySheet / PhotoLogSheet show a "Time logged" picker when logging to a past day. Initialized to noon (legacy default), user can dial in the actual time.
- EditEntrySheet's "When" section has both Date and Time pickers, each editing only its own component. Lets you retroactively fix any entry's time.
- SearchSheet quick-add intentionally skips — stays one-gesture; fix via EditEntrySheet.

*Trends tab*
- 4th tab. Range selector: 7 days / 30 days / Custom (with date pickers).
- **Weight section (v1.8, always visible):** Latest weight, average over range, change in range (green ↓ / orange ↑). NavigationLink → WeightEntriesSheet for logging + swipe-delete + 5-second undo. Skipped Health-imported entries don't delete from Health on soft-delete commit.
- **Macros (daily average)** for calories + protein + carbs + fat with goal progress bars.
- **Energy section (v1.9, always visible when "Show calories burned" is on):** Avg Active, Avg Total Burned, Avg Net (consumed − total burned). Avg Net only includes days with BOTH consumed and burn data. Days with no burn samples are excluded from all three averages.
- **Distribution by meal (v1.8.4):** four rows (Breakfast / Lunch / Dinner / Snacks), each with `Cal X% · P X% · C X% · F X%` chips showing share of range total per macro.
- **Water (daily average)** with goal bar.
- **Honest "based on N of M days" caption** when coverage is partial. Preserves nil ≠ 0.
- Empty state when range has no data. Hidden gracefully when only weight data is present.

*Meal-time schedule (v1.8: now user-configurable)*
- Three windows in Settings → Meal time schedule: Breakfast / Lunch / Dinner, each with start + end hour pickers.
- Defaults match the v1.7 hardcoded schedule (6–10 / 12–14 / 17–20).
- Each window can wrap midnight (e.g. Dinner 22:00–02:00 for night shift).
- Anything outside the named windows defaults to Snack.
- "Reset to defaults" button.

*Late-night snack confirmation*
- Saving a snack inside the configured late-night window prompts: *"Late-night snack? It's getting late..."* with Cancel / Log it anyway.
- Configurable: toggle + Start/End hour pickers. Defaults 8pm–6am, enabled.
- Persisted via @AppStorage. Window can wrap midnight.
- Wired into all save paths.

*Edit any logged entry*
- Tap any entry on a meal card's detail sheet → EditEntrySheet mirrors Manual Entry pre-populated.
- All 19 nutrient fields editable, plus name, brand, servings, unit (Custom… supported), meal.
- "When" section with Date picker (v1.7.4) + Time picker (v1.8.3).
- Save mutates the existing FoodEntry; SwiftData persists. LibraryFood.useCount bumps. Apple Health sync deletes old samples + writes new ones (v1.8.2).

*Confirm screen (barcode + search + Most Used results)*
- Save in top-right of nav bar. Tap grams field → highlights ready to replace.
- Adjusting grams scales every nutrient in real time.
- Meal picker respects pre-tagged context if set, else time-of-day default.
- Past-day time picker section when applicable.

*Notification reminders (v1.8.1)*
- Three independent toggles in Settings → Reminders: Breakfast / Lunch / Dinner. Each with its own time picker. Defaults all off.
- First toggle ON triggers the iOS notification permission prompt. Denial reverts the toggle and offers an alert with "Open Settings" deep link.
- Tap a fired notification → app opens to Today tab → MealDetailSheet for that meal opens (deep link).
- Daily-repeating `UNCalendarNotificationTrigger`. Re-scheduling on time change replaces the previous request (same identifier).

*Apple Health calories burned (v1.9 — read-only)*
- New separate toggle in Settings → Apple Health → "Show calories burned" (independent of the master Sync toggle). Defaults off.
- First toggle ON triggers HealthKit's read-permission prompt for `activeEnergyBurned` + `basalEnergyBurned`. The toggle stays ON regardless of grant outcome — HK intentionally hides read-grant status. If the user denies, the UI shows "—".
- Reads are on-demand and not cached locally. Today re-queries on selectedDate change; Trends re-queries on range change.
- Net calories goal (configurable in Daily goals when this toggle is on). Stored via `@AppStorage` with sentinel-0 fallback: 0 = "track the daily calorie goal automatically." Schema-clean.
- CSV export adds a 4th file (energy.csv) when this toggle is on. Columns: date, activeEnergyKcal, basalEnergyKcal, totalBurnedKcal, consumedKcal, netCaloriesKcal. One row per day with any non-nil data. Nil → empty cell.

*Apple Health sync (v1.8.2)*
- Master toggle in Settings → Apple Health → "Sync to Apple Health." Defaults off.
- First toggle ON triggers HealthKit's per-type permission sheet (~20 toggles inside). Denial reverts the toggle.
- **Writes:** food entries push individual nutrient samples (calories, protein, carbs, fat, sat/poly/mono fat, fiber, sugar, cholesterol, sodium, potassium, calcium, iron, magnesium, vitamins A/C/D); water pushes `dietaryWater`; weight pushes `bodyMass`. Trans fat skipped (no HK type). Food entries are saved as individual quantity samples (NOT HKCorrelation) so deletes route by type.
- **Deletes** cascade: soft-delete commit, EditEntrySheet save, and SearchSheet quick-add undo all wipe corresponding Health samples. Always attempts when an entry has `healthSampleID`, even with the master toggle off, so orphans don't accumulate.
- **Import weight from Apple Health** button (visible when toggle ON): pulls bodyMass samples written by other sources (Apple Watch, scales) into the WeightEntry table. Dedupes by `healthSampleID`. Imported entries are flagged `importedFromHealth = true` so in-app deletes leave the source Health data alone.
- **CSV export now includes a third file:** weight.csv alongside food.csv + water.csv.
- All write failures are silent — best-effort per sample.

*Smart "your usual?" suggestions (v1.8.6)*
- Heuristic: most-frequently-logged food in a meal slot over the last 14 days, threshold ≥ 3 occurrences. Snacks excluded.
- Surfaces as the orange banner described above on the Today tab.
- Toggle in Settings → Smart suggestions → "Suggest your usual." Defaults ON.

*Health Data tab (v2.2, extended v2.3a)*
- New 3rd tab, between Workouts and Trends. SF Symbol `heart.text.square`.
- Read-only Apple Health dashboard. Reads vitals + sleep + blood pressure on demand from HealthKit; nothing is cached locally — same invariant as v1.9 energy and v2.0 workouts.
- First open requests READ permission for ~12 types at once (sleep, 9 single-value vitals, systolic + diastolic). Reuses the existing `NSHealthShareUsageDescription` privacy string from v1.8.2.
- Tile grid: **Sleep** (last night's asleep duration + REM / Core / Deep stage pills), **Blood pressure** (latest pair as `120/80` or `–` with a "manual entry or cuff" hint), plus 9 single-value vital tiles — Heart rate, Resting HR, HRV, Blood oxygen, Respiratory rate, Steps, VO2 max, Wrist temperature, Walking double support.
- Each tile is tappable and pushes a trend page with a 7d / 30d range picker and a Swift Charts line + point chart. **Missing days are gaps, not zeros** (nil ≠ 0). Trend pages also show Average / Min / Max / Days-with-data underneath the chart.
- Sleep trend plots nightly asleep duration in hours. BP trend plots systolic + diastolic as two color-coded series.
- Honest "denial = no data" disclaimer at the bottom: HealthKit hides read-grant status, so a permanently `–` tile may mean either no data exists OR you denied permission. Check the Health app's permission screen if unsure.
- **Architecture**: a descriptor-driven generic path. `HealthService.healthMetrics: [HealthMetric]` is the single source of truth for the vital list — adding a future metric is a one-line entry. Generic readers `readMetricToday` / `readMetricByDay` dispatch on `MetricAggregation` (`.average` for rate-style metrics; `.sum` for steps; `.latest` for VO2 max + wrist temp). Sleep and BP have bespoke readers because they don't fit the single-value pattern.
- **v2.3a**: a "Lab results" entry row below the tile grid pushes the labs surface (manual entry, photo import, marker trends, marker merge tool).

*Lab results (v2.3a — medical data; display & flag only, no interpretation)*
- New surface reached from Health Data → "Lab results." Stores blood-panel-style results from two import paths: manual entry, and photo of a printed report or screenshot (Claude transcribes → mandatory human review → save).
- **Safety rule (non-negotiable)**: this surface DISPLAYS values and FLAGS them against the lab's OWN printed reference range. It does NOT INTERPRET your results — no commentary on what abnormal values might mean, no medical advice, no app-invented ranges. A result with no printed numeric range shows NO flag, never a guessed one. The single out-of-range indicator string anywhere is "out of range" — neutral, factual.
- **Manual entry**: pick collected date + source (LabCorp / Quest / PCP / etc.) → add result rows (testName, value or qualitative text, unit, range low/high or text). Save commits the panel + results.
- **Photo / PDF import**: three entry points on one sheet — take a photo, pick a photo from the library, or pick a **PDF** (e.g. the direct PDF export from Apple Health → Browse → Lab Results → Share → PDF). The app sends the file to Claude with a transcription-only prompt (no interpretation, no unit conversion, no invented ranges) and lands you on a **mandatory editable review screen** showing every extracted row with an "AI-extracted — verify against your report before saving" banner. Every field is editable; misread rows can be deleted; missed rows can be added. Save commits only the reviewed version. **Nothing extracted by Claude ever persists directly.** PDFs are read natively (Claude's `document` content type) — multi-page reports go in one shot, up to 32 MB / 100 pages.
- **Apple Health Records (FHIR) direct ingestion**: planned for v2.3a but pulled — the `com.apple.developer.healthkit.access = ["health-records"]` entitlement requires a paid Apple Developer Program account ($99/yr) AND a per-bundle-ID approval from Apple. On the free dev team this project uses, the provisioning profile is rejected. Workaround: export the lab panels you want from Apple Health → Browse → Lab Results → Share → PDF and run them through the photo/PDF import path above; Claude transcribes the same FHIR-sourced values. Full FHIR ingestion returns as v2.3b if paid membership ever lands.
- **Per-panel detail**: lists every result with value (or qualitative text), unit, range (when printed), and a neutral colored dot — green when the numeric value is inside the printed numeric range, orange "out of range" otherwise, nothing at all when no numeric range is printed.
- **Marker trends**: pick a marker (auto-grouped by `LabMarker.normalize(testName)` — exact-match-on-stripped-name, so "HbA1c" / "Hb-A1c" / "HB A1C" auto-merge). Chart shows numeric samples over time. Shaded green band shows the printed reference range ONLY when every plotted point's range agrees strictly — when ranges vary or are absent, no band is drawn and a footer notes why. Qualitative samples (Negative / Detected / "<0.1") are listed below the chart, never charted.
- **Marker merge tool**: for differently-named tests that mean the same marker (Hemoglobin A1c ↔ HbA1c), open Merge markers, tap two or more markers, pick one as canonical, the others alias to it. Auto-merge is intentionally limited to exact-after-normalization matches because a wrong merge (two distinct tests on one trend) is worse than a split.
- **Soft delete on panels**: swipe a panel → 5-second undo toast. Cascade fires through to LabResults only on commit, same pattern as the rest of the app.
- **Schema**: two new @Models — `LabPanel` (cascade-owns) `LabResult`. Bumps container from 14 to 16 model types. Schema change → reinstall required.

*Workouts tab (v2.0)*
- 2nd tab in the TabView (since v2.2), between Food and Health Data. SF Symbol `figure.run`.
- Reads workouts from Apple Health (HKWorkout samples) on demand — never cached locally, matching the v1.9 invariant. Refreshes on tab appear and pull-to-refresh.
- First open requests READ permission for HKWorkout + activeEnergyBurned + distanceWalkingRunning + distanceCycling via the existing `NSHealthShareUsageDescription` privacy string.
- **Today summary card** at top: three stat tiles — Workouts count today / Active calories today (kcal) / Total duration today (`1h 5m` style). All three show `—` when no workouts logged today (nil ≠ 0).
- **Apple Fitness section (split in v2.1a.1)**: shows ONLY today's workouts inline so the daily-use controls below stay reachable without a long scroll. A "See previous workouts ›" navigation row pushes a separate `WorkoutHistoryView` page listing the rest of the last 30 days grouped by day (Yesterday / `Mon, May 4`), newest first. Same row styling on both: activity SF Symbol + display name, start time, duration, active calories (or `—`), miles for run/walk/hike/cycle only. Empty states: "No workouts logged today." inline when today is empty but earlier days have data; the full "No workouts found" card only when the 30-day window has nothing at all.
- Composable section structure leaves room for v2.1's daily bodyweight tracker and strength routines without re-architecting.
- Active calories come from `workout.statistics(for: .activeEnergyBurned)` (the modern API; the deprecated `workout.totalEnergyBurned` is NOT used). Distance maps `running/walking/hiking → distanceWalkingRunning` and `cycling → distanceCycling`; everything else is nil.

*Daily section in the Workouts tab (v2.1a)*
- Two append-style cards: **Pushups** and **Situps**. Each shows today's running sum (or `–` for nil ≠ 0 when zero entries today), a custom-count text field, and a Log button. Each Log inserts a new ExerciseRepEntry with `loggedAt = now` — the displayed number is the sum, not the latest entry.
- Long-press (or tap the count's pencil affordance) on the big number → opens DailyRepsSheet listing today's individual bursts with swipe-delete + 5-second undo toast, exactly like WaterEntriesSheet.
- **Stretched today** card: single toggle/checkmark. Tap flips the day's StretchDay row (creates it if today's row doesn't exist). Binary by design — no duration tracking.

*Strength section in the Workouts tab (v2.1a)*
- Three sheets accessible from this section:
  - **Routines** → list + create + edit + delete reusable StrengthRoutine templates. Each routine holds an ordered list of RoutineExercises with optional target sets / reps / weight. Editing a routine uses replace-all on save (safe — sessions don't reference the routine's exercises by ID).
  - **Log a session** → pick a routine (or "Blank session"). Picking a routine pre-fills the exercise list and displays each exercise's targets as HINTS (e.g. "Target: 3×8 @ 135 lbs"). Targets are **display-only**; they are never copied into stored set values. For each exercise the user adds LoggedSets one at a time (weight × reps), with auto-incrementing setNumber. Optional duration field on the session. Exercises with zero logged sets are skipped on save to keep history clean.
  - **History** → reverse-chrono list of past StrengthSessions with date, routine name, exercise + set counts, and duration. Tap → read-only SessionDetailView showing each exercise and its sets. Swipe-delete with 5-second undo at the list level (cascade-deletes the session's exercises and sets atomically).
- **Strength + daily-tracker data is intentionally in-app only.** No HealthKit fields, no HealthSync calls. HealthKit can't store weight/reps/sets, and writing strength workouts from the app would double-count against the Apple Watch's already-tracked calorie burn (which appears in the Today energy strip and Trends). The session's duration field is informational only.

*Strength schedule (v2.1b)*
- New **Schedule** entry point in the Workouts tab → Strength section. Sheet with 7 weekday rows (Monday → Sunday), each a Picker over current routines + Rest. Pick one routine per day or leave Rest.
- A non-tappable **"Today: {routine name or Rest}"** indicator at the top of the Strength section reflects the current weekday's pick. Updates instantly when the schedule changes.
- **Log a session** pre-selects today's scheduled routine when opened (which auto-fills the routine's exercises). Manual picker override still works.
- Storage is a single `@AppStorage("strengthWeeklySchedule")` JSON string mapping weekday number → routineID UUID. No schema change, no new @Model.
- **Robustness**: if a stored routine UUID no longer resolves (the user deleted that routine), the day silently falls back to Rest — no crash, no dangling name surfaced.

*Strength trends (v2.1b)*
- New **Trends** entry point in the Workouts tab → Strength section (separate from the food-oriented Trends tab — strength trends live with strength logging).
- Pick an exercise from a menu of every distinct name across all your non-soft-deleted sessions (case-insensitive dedupe, displayed in the latest casing you used).
- **Per-session top-set weight**: max `weightLbs` across that exercise's sets in that session (sets with nil weight are excluded). Answers "is the weight going up."
- **Per-session estimated 1RM** via Epley `weight × (1 + reps/30)`, taking the max over sets with BOTH non-nil weight AND non-nil reps. Always labeled "Est." / "(Epley)" — never presented as a lifted weight. Normalizes across rep ranges so 135×8 and 145×3 are comparable.
- The two stats are **computed independently** per session — the top-weight set and the top-e1RM set within one session may be different sets.
- **Two line+point charts** (Swift Charts) for the two metrics. Drawn only when there are ≥ 2 sessions; a single session shows its data point with a "Need 2+ sessions to show a trend." caption and no fake line.
- **Latest vs previous delta** rows at the top: green ↑ when the metric went up, orange ↓ when it went down, "–" when no prior session exists for that exercise.
- **Raw sets per session** listed below the charts so the actual logged data is never hidden behind the estimate. Sets with nil weight or reps display raw (`135 × –`) but are excluded from the trend math.
- Empty state when no logged sessions exist anywhere.

*CSV import (v2.0.1, extended v2.2.3)*
- New row in Settings → Data → **Import data** opens a sheet that supports `.fileImporter` for picking any subset of food / water / weight / **strength sessions / strength routines / rep entries / stretch days** CSVs (renamed files are fine — header is sniffed, not the filename).
- **Empty-table guard per type:** every supported table must be empty (no non-soft-deleted rows; routines + stretch days have no soft-delete so any row counts) before that file's import will run. If non-empty, the file is reported as skipped with an orange message and zero rows insert. There is intentionally no dedupe / merge / matching logic.
- **Designed for one purpose**: restoring history after a schema-change reinstall. Use after a fresh app install, never on a populated app.
- Imported FoodEntry rows call `LibraryFoodUpsert` (rebuilds search library + useCount) and **skip** HealthSync (they're historical restorations, not new logs — would duplicate or orphan HK samples otherwise).
- Source provenance is preserved per-row from the CSV's source column. Only a blank source cell falls back to `"import"`. So sparkles-icon `source == "suggestion"` rows still render correctly after a round-trip.
- Nil ≠ 0 round-trip: a food entry with a blank optional nutrient in the CSV (empty cell) parses back to `Double? = nil`, never 0. Same applies to strength (weight_lbs, reps, target_sets / reps / weight_lbs, duration_minutes, routine_name). Blank required fields (name, loggedAt, servings, calories, protein/carbs/fat, amountOz, weightLbs, set_number, exercise_order, count, stretched) mark the row malformed and skip it.
- **Strength sessions** are flattened to one row per LoggedSet. Import groups rows back into StrengthSession → LoggedExercise → LoggedSet by (session_date, session_time, routine_name, duration_minutes) at the session level, then (exercise_name, exercise_order) within a session. **Strength routines** are flattened to one row per RoutineExercise; import groups by (routine_name, routine_order, created_at). **Zero-set exercises and zero-exercise routines are not exported and therefore can't be re-imported** — they shouldn't exist in practice (LogSessionSheet skips empty exercises on save).
- Imported strength / daily-tracker data does NOT touch HealthKit (v2.1a "in-app only" rule).
- Energy CSV: detected and reported as "not stored locally" since it's read-only from Health.

*Settings*
- Save button in top-right nav bar.
- Daily goals for calories / protein / carbs / fat / water.
- **More nutrient goals** sheet — editable targets for all 14 secondary nutrients.
- **Late-night snack alert** toggle + start/end pickers.
- **Meal time schedule** (v1.8): per-meal start/end pickers + Reset to defaults.
- **Reminders** (v1.8.1): per-meal toggle + time picker.
- **Smart suggestions** (v1.8.6): single toggle.
- **Apple Health** (v1.8.2 + v1.9): two independent toggles — "Sync to Apple Health" (write food/water/weight) and "Show calories burned" (read active + basal energy). Import weight button visible when sync is on.
- **Data section:** Export data (food + water + weight + strength sessions + strength routines + rep entries + stretch days CSVs, plus energy.csv when burn-toggle is on), **Import data (v2.0.1, extended v2.2.3)** (restore all of the above from CSV — empty-table guarded per type), Reset food library.
- **API keys section:** compact rows with Set/Not set status.

*App icon*
- Custom devil-fruit-themed icon (purple swirly fruit on lavender, Gemini-generated PNG).

*Throughout*
- Haptic feedback on logging, saving, destructive actions.
- Save/Log buttons dismiss the keyboard.
- Done button on numeric keypad in long forms.
- Numeric fields select-all-on-focus.
- Numbers round cleanly: "3" not "3.0", "<0.1" for tiny values, "2.5" for fractional.

**Tracked nutrients (19 fields + water + weight)**
Calories, Protein, Carbs, Fiber, Sugar, Total Fat, Saturated, Polyunsaturated, Monounsaturated, Trans, Cholesterol, Sodium, Potassium, Vitamin A, Vitamin C, Vitamin D, Calcium, Iron, Magnesium. Plus water (oz) and weight (lbs) as separate models.

Critical design choice: optional fields use `Double?`. Empty form fields stay nil. Nil ≠ 0 anywhere — the breakdown displays "–" for unknown values rather than misleading zeros. CSV exports render nil as empty cells. Trends rows say "based on N of M days" so partial-coverage averages stay honest.

**Tech stack**
- iOS 18+ (deploys to iOS 26.4 on Mike's iPhone 17 Pro Max)
- Xcode 26.4
- SwiftUI + SwiftData
- HealthKit (v1.8.2 — works on free dev team with the capability + Info.plist usage strings)
- UserNotifications (v1.8.1)
- VisionKit `DataScannerViewController` for barcode scanning
- `UIImagePickerController` (wrapped in SwiftUI) for camera capture
- Open Food Facts API (free, no key) for product lookup
- Anthropic Messages API (`claude-sonnet-4-6`) for photo nutrition estimation — supports multi-image (v1.8.5)
- USDA FoodData Central API (free, requires personal key) for food name search
- CryptoKit SHA256 hashing of resized image pixel data for photo cache keys (combined hash for multi-photo, v1.8.5)
- Keychain (`KeychainStore`) for Anthropic + USDA API keys
- @AppStorage / UserDefaults for late-night warning, meal-window config, reminder toggles + times, smart-suggestion toggle, Health sync toggle
- Git, committed phase by phase via terminal

**Data models (16 total)**
- `FoodEntry` — all 19 nutrients + meta (loggedAt, mealType, source, barcode, pendingDeleteAt, healthSampleID JSON)
- `UserGoals` — daily targets for the 5 main + 14 optional nutrients
- `CachedFood` — barcode → product cache
- `WaterEntry` — amountOz, loggedAt, pendingDeleteAt (v1.8), healthSampleID (v1.8.2)
- `CachedPhotoEstimate` — image hash → estimate cache (single + multi-photo combined hashes)
- `LibraryFood` — passive food library, hybrid per-100g / per-serving storage
- `WeightEntry` (v1.8) — weightLbs, loggedAt, pendingDeleteAt, healthSampleID, importedFromHealth
- `ExerciseRepEntry` (v2.1a) — pushup/situp burst (kind, count, loggedAt, pendingDeleteAt)
- `StretchDay` (v2.1a) — date, stretched
- `StrengthRoutine` (v2.1a) — name, order, createdAt, cascade-owns RoutineExercise
- `RoutineExercise` (v2.1a) — target template line (sets/reps/weight optional)
- `StrengthSession` (v2.1a) — loggedAt, routineName, durationMinutes, pendingDeleteAt, cascade-owns LoggedExercise
- `LoggedExercise` (v2.1a) — name, order, cascade-owns LoggedSet
- `LoggedSet` (v2.1a) — weightLbs?, reps?, setNumber
- `LabPanel` (v2.3a) — collectedDate, source, importedAt, pendingDeleteAt, cascade-owns LabResult
- `LabResult` (v2.3a) — testName, normalizedName, loincCode?, value?, valueText?, unit?, refRangeLow?, refRangeHigh?, refRangeText?, order, fhirID? (dedupe primitive for Apple Health import)

**Project structure**
```
FoodJournal/
├── FoodJournalApp.swift                entry point, SwiftData container (7 models),
│                                        owns NotificationCoordinator
├── FoodJournal.entitlements            HealthKit capability
├── Info.plist                          (privacy strings live in pbxproj as
│                                        INFOPLIST_KEY_* build settings)
├── Assets.xcassets/AppIcon.appiconset  custom devil-fruit icon
├── Models/
│   └── Models.swift                    FoodEntry, UserGoals, CachedFood, WaterEntry,
│                                        CachedPhotoEstimate, LibraryFood, WeightEntry,
│                                        LibraryFoodUpsert helper, FoodFormat enum
├── Services/
│   ├── OpenFoodFactsService.swift      barcode → product (full nutrition) +
│   │                                    v2.2.1: text-search (SearchHit shape mirrors
│   │                                    USDA's; partial products kept, junk skipped)
│   ├── ClaudeVisionService.swift       multi-photo → nutrition estimate; pixel-hash
│   ├── USDAService.swift               food name → search hits (per-100g, normalized).
│   │                                    v2.2.1: USDAError.http carries the response body
│   │                                    so api.data.gov's actual complaint reaches the UI.
│   ├── LibraryService.swift            local library substring search + recency
│   ├── MealTimeHelper.swift            user-configurable meal windows + late-night
│   ├── KeychainStore.swift             parameterized key storage
│   ├── NotificationService.swift       v1.8.1: daily meal reminder schedule/cancel
│   ├── NotificationCoordinator.swift   v1.8.1: @Observable UN delegate
│   ├── HealthService.swift             v1.8.2: HealthService + HealthSync orchestration
│   ├── UsualSuggestionService.swift    v1.8.6: "your usual?" suggestion logic
│   ├── StrengthSchedule.swift          v2.1b: AppStorage-backed weekday → routineID
│   │                                    JSON map. Decode/encode helpers; resolution
│   │                                    to SwiftData is the view's job.
│   └── HealthMetrics.swift             v2.2: extension HealthService. Descriptor list
│                                        for 9 single-value vitals + generic readers
│                                        (today + range). SleepNight + BPReading types
│                                        with bespoke readers. Adds workout permission
│                                        helper that prompts for all v2.2 types at once.
└── Views/
    ├── RootView.swift                  v2.2 — TabView with 5 tabs in order:
    │                                    Food (was Today) · Workouts · Health Data ·
    │                                    Trends · Settings. Hoisted selectedDate,
    │                                    notification deep-link to tag 0 (Food).
    ├── TodayView.swift                 hosts the Food tab. Dashboard, smart-suggestion
    │                                    banner, P/C/F line on meal cards, water +
    │                                    suggestion undo handling
    ├── AddFoodView.swift               DORMANT as of v2.2 — was the Add tab, removed
    │                                    from the TabView. File preserved for revival.
    ├── TrendsView.swift                Weight section (always-visible), Distribution
    │                                    by meal section, WeightEntriesSheet
    ├── WorkoutView.swift               v2.0 + v2.1a / v2.1a.1 / v2.1b: Workouts tab.
    │                                    Today summary + Apple Fitness (today inline
    │                                    only, "See previous workouts ›" pushes the
    │                                    rest) + Daily section (pushup/situp append
    │                                    cards + stretch toggle) + Strength section
    │                                    with 6 items (Today indicator → Routines →
    │                                    Schedule → Log session → History → Trends).
    │                                    Composable sections.
    ├── WorkoutHistoryView.swift        v2.1a.1: full-page Apple Fitness history pushed
    │                                    from Workouts tab. Receives pre-filtered
    │                                    previous-workouts array, no new HK query.
    ├── DailyRepsSheet.swift            v2.1a: manage today's individual ExerciseRepEntry
    │                                    bursts for one kind. Mirrors WaterEntriesSheet.
    ├── RoutinesSheet.swift             v2.1a: list/create/edit/delete StrengthRoutines
    │                                    + nested RoutineEditorSheet
    ├── LogSessionSheet.swift           v2.1a: log a StrengthSession against a routine
    │                                    (or blank). Targets are display-only hints.
    ├── SessionHistorySheet.swift       v2.1a: reverse-chrono history + read-only detail.
    │                                    Cascade-safe soft-delete with 5s undo.
    ├── ScheduleSheet.swift             v2.1b: 7 weekday rows (Mon→Sun display),
    │                                    routine-picker per day, dangling-ID fallback
    │                                    to Rest.
    ├── StrengthTrendsSheet.swift       v2.1b: per-exercise charts. Top-set weight +
    │                                    est. 1RM (Epley), computed independently per
    │                                    session. Swift Charts. Raw sets disclosure.
    ├── HealthMetricsView.swift         v2.2: Health Data tab. Tile grid (sleep + BP
    │                                    specials + 9 vitals); each tile pushes a 7d/30d
    │                                    trend chart. Missing days are gaps, never 0.
    │                                    Self-contained NavigationStack.
    ├── BarcodeScannerSheet.swift       defaultMeal + defaultDate
    ├── PhotoLogSheet.swift             v1.8.5 multi-photo strip + v1.8.5 low-confidence
    │                                    card + v2.2.2 typed-context TextField between
    │                                    photos and Analyze; context threads through the
    │                                    cache lookup and the Claude API call.
    ├── SearchSheet.swift               library + USDA + OFF unified search (v2.2.1).
    │                                    Library swipe-add (v1.7.3) with Health-sync.
    │                                    Concurrent USDA + OFF behind one debounce;
    │                                    MergedHit ranks results with dedupe + source
    │                                    tags; in-flight task cancellation per keystroke.
    ├── CSVExportSheet.swift            food + water + weight + (v1.9) energy CSV via
    │                                    share sheet
    ├── CSVImportSheet.swift            v2.0.1: inverse of CSVExportSheet. Per-type
    │                                    empty-table guard, RFC 4180 parser,
    │                                    LibraryFoodUpsert on food rows, skips
    │                                    HealthSync, preserves CSV source column
    ├── NutritionBreakdownSheet.swift   respects selectedDate + pendingDeleteAt
    ├── NutrientGoalsSheet.swift        editable goals for the 14 secondary nutrients
    └── AuxViews.swift                  ConfirmFoodView, ManualEntrySheet, EditEntrySheet,
                                         SettingsView (Meal schedule, Reminders, Smart
                                         suggestions, Apple Health, Data section with
                                         Export + v2.0.1 Import + Reset library),
                                         AnthropicKeySheet, USDAKeySheet, RelogSheet
                                         (dormant), helpers
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R.

**External services (optional but recommended):**
- Photo logging: paste an Anthropic API key in Settings → API keys → Anthropic API key (`sk-ant-...`).
- Food search: paste a USDA API key in Settings → API keys → USDA API key (free, from api.data.gov/signup).
- Apple Health sync: toggle on in Settings → Apple Health → "Sync to Apple Health." First toggle triggers the iOS permission sheet.
- Notification reminders: enable per-meal in Settings → Reminders. First toggle triggers permission prompt.

**Xcode manual setup (already done; for new sessions / fresh checkouts):**
- HealthKit capability: Signing & Capabilities → `+` Capability → HealthKit.
- **NOT enabled (free dev team blocker):** "Clinical Health Records" sub-capability. Tried during v2.3a development; provisioning profile signing fails on personal teams with the error "Personal development teams do not support the HealthKit Access (Verifiable Health Records) capability." Apple gates this entitlement just like CloudKit. Re-attempt only after paid Developer Program enrollment + per-bundle-ID Apple approval.
- Info tab → add `Privacy - Health Share Usage Description` and `Privacy - Health Update Usage Description`. Both wired as `INFOPLIST_KEY_*` build settings.

**Schema-change reinstalls.** Anytime fields are added to `@Model` classes, delete the app from your phone (long-press icon → Remove App → Delete App), then run fresh from Xcode. Always export CSV first via Settings → Data → Export. **Then restore via Settings → Data → Import data after the fresh install** — see CSV import below. So far: v1.8, v1.8.2, v2.1a (7 new @Models for strength + daily tracker — first @Relationship cascades in the schema), **v2.3a (2 new @Models for lab panels + results — third nested-cascade pattern; first medical data)** required reinstalls; v1.8.1, v1.8.3, v1.8.4, v1.8.5, v1.8.6, v1.9, v2.0 (Workouts tab + display-name rename), v2.0.1 (CSV import), v2.1a.1 (Apple Fitness split — view-only), v2.1b (strength schedule + per-exercise trends — view + AppStorage only), v2.2 (Health Data tab + tab bar reorg — view + HealthKit reads only), v2.2.1 (Open Food Facts text search + merged search results — view + service only), v2.2.2 (typed-context field on photo estimate — view + service only), v2.2.3 (CSV export + import for strength + daily-tracker tables — extends CSVExportSheet + CSVImportSheet) were schema-clean.

**Project location:** `~/Desktop/my stuff/apps/foodjournal/foodjournal/` (path has a space — shell-quote it).

**Committing changes:** use terminal, not Xcode's UI:
```
cd ~/Desktop/"my stuff"/apps/foodjournal/foodjournal
git add <specific files>
git commit -m "v1.X.Y: short description"
git log --oneline -5
```

## Known issues / quirks

- **Open Food Facts unit conversions** — sodium/calcium/iron/magnesium/potassium are converted from grams to mg, vitamins A/D from g to µg, vitamin C from g to mg. Right for ~95% of products. Dramatic outliers may need one-off fixes.
- **No error UI for network failures on barcode scan** — Open Food Facts timeouts surface as "not found."
- **Force-quitting the app while an undo toast is showing** commits the pending delete on next launch. Acceptable since it's a 5-second window.
- **Manual entry totals-mode misuse** is resolved by the toggle. Old pre-v1.7 entries with the 38,000-calorie pattern can be fixed via EditEntrySheet or deleted and re-logged.
- **EditEntrySheet has no totals toggle** — by design. To edit a totals-mode entry's amount, delete and re-log via Manual entry totals mode.
- **Library per-serving fallback:** when a LibraryFood was originally logged with a non-gram unit, picking it from search/Most Used lands on Confirm with grams = 100. Macros are technically per-serving but presented "for 100g." Real-world impact small.
- **SearchSheet quick-add is library-only** — USDA results have no swipe. To log a USDA food, tap → Confirm.
- **SearchSheet quick-add late-night warning** fires the same alert as other paths. Slight friction; matches the rest of the app.
- **Search results may include duplicates** — Foundation and SR Legacy datasets often both contain the same food (and the same product can appear in USDA Branded + Open Food Facts). v2.2.1's cross-source dedupe collapses USDA-vs-OFF near-duplicates on name + brand + ±15% calorie tolerance, preferring USDA — but it's heuristic. Occasionally over-collapses (hides a genuinely different food) or under-collapses (lets a true dup through). Tune in `mergeAndDedupe` in SearchSheet.swift.
- **OFF results are crowd-sourced and frequently partial** — many products have only calories + macros, with optional nutrients (fiber, sugar, vitamins) missing. These display as `–` in the breakdown thanks to the nil ≠ 0 enforcement, but visually you'll see more `–` on OFF-sourced entries than USDA. That's coverage's cost, working as intended. The source tag on each row makes it easy to eyeball-distrust an OFF entry if it looks wrong.
- **USDA HTTP 400 is silently swallowed** — api.data.gov's fronting nginx occasionally returns 400 Bad Request on rapid / bursty requests. v2.2.1 specifically catches this and shows no USDA results that round (no red error). Every other USDA error (missing key, 401/403/429, network failure, decode error) still surfaces with the actual cause text from api.data.gov.
- **SearchSheet quick-add on past day defaults to noon.** No time picker on quick-add; fix via EditEntrySheet's Time picker.
- **Schema-change reinstalls used to be lossy** — exporting then reinstalling threw away the on-device data with no way back. **As of v2.0.1 this is solved**: export via Settings → Data → Export, reinstall fresh, then restore via Settings → Data → Import data. The importer has a per-type empty-table guard, so it ONLY runs into a fresh install — protecting you from accidentally double-importing into a populated app. There is no dedupe/merge; the design assumption is "import only on a fresh install, once."
- **HealthKit "Show All Data" view shows nutrients individually, not grouped as a meal.** Food entries are saved as individual quantity samples (not HKCorrelation) because correlation types can't be authorized for writes. Per-nutrient summary screens (Calories Consumed / Protein / etc.) are unaffected.
- **HealthKit write failures are silent.** If a specific nutrient type was denied write permission, that sample is skipped. The remaining ones still write.
- **Smart-suggestion dismissal is in-memory only.** Tapping X hides for the rest of the view's lifetime. App relaunch resets. Acceptable for v1.
- **RelogSheet is dormant but maintained.** Has v1.7.1 defaultDate threading and v1.8.2 HealthSync wiring for consistency. Unreachable from UI.
- **Custom devil-fruit icon is AI-generated.** Original-art-enough for personal use; replace before any App Store submission.
