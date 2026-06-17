# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for three external calls (Open Food Facts for barcode lookups, Anthropic Claude for photo estimation, USDA FoodData Central for food name search) and an optional two-way Apple Health sync.

Built collaboratively across multiple sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.9)

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
- **Search foods** — unified search across the local food library (passively populated from every save path) and USDA FoodData Central. Library results stream instantly; USDA follows after 300ms debounce. "Branded foods" toggle. Tap → Confirm.
- **Library swipe-add (v1.7.3)** — swipe right on any library row → green **Quick add** button creates a FoodEntry directly with default amounts (100g for per-100g foods, 1 serving otherwise). 5-second undo. Late-night warning still fires for snacks.
- **Scan barcode** — Open Food Facts lookup pulls 19 nutrients where available.
- **Photo estimate (v1.8.5: now multi-photo)** — opens the camera. After capture you see a thumbnail strip; up to 3 photos for the same meal from different angles. X to remove a thumb. Analyze sends all to Claude. Low-confidence card with Re-analyze (cache-bypassing) + Add angle.
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

*Settings*
- Save button in top-right nav bar.
- Daily goals for calories / protein / carbs / fat / water.
- **More nutrient goals** sheet — editable targets for all 14 secondary nutrients.
- **Late-night snack alert** toggle + start/end pickers.
- **Meal time schedule** (v1.8): per-meal start/end pickers + Reset to defaults.
- **Reminders** (v1.8.1): per-meal toggle + time picker.
- **Smart suggestions** (v1.8.6): single toggle.
- **Apple Health** (v1.8.2 + v1.9): two independent toggles — "Sync to Apple Health" (write food/water/weight) and "Show calories burned" (read active + basal energy). Import weight button visible when sync is on.
- **Data section:** Export data (now exports food + water + weight CSVs), Reset food library.
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

**Data models (7)**
- `FoodEntry` — all 19 nutrients + meta (loggedAt, mealType, source, barcode, pendingDeleteAt, healthSampleID JSON)
- `UserGoals` — daily targets for the 5 main + 14 optional nutrients
- `CachedFood` — barcode → product cache
- `WaterEntry` — amountOz, loggedAt, pendingDeleteAt (v1.8), healthSampleID (v1.8.2)
- `CachedPhotoEstimate` — image hash → estimate cache (single + multi-photo combined hashes)
- `LibraryFood` — passive food library, hybrid per-100g / per-serving storage
- `WeightEntry` (v1.8) — weightLbs, loggedAt, pendingDeleteAt, healthSampleID, importedFromHealth

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
│   ├── OpenFoodFactsService.swift      barcode → product (full nutrition)
│   ├── ClaudeVisionService.swift       multi-photo → nutrition estimate; pixel-hash
│   ├── USDAService.swift               food name → search hits (per-100g, normalized)
│   ├── LibraryService.swift            local library substring search + recency
│   ├── MealTimeHelper.swift            user-configurable meal windows + late-night
│   ├── KeychainStore.swift             parameterized key storage
│   ├── NotificationService.swift       v1.8.1: daily meal reminder schedule/cancel
│   ├── NotificationCoordinator.swift   v1.8.1: @Observable UN delegate
│   ├── HealthService.swift             v1.8.2: HealthService + HealthSync orchestration
│   └── UsualSuggestionService.swift    v1.8.6: "your usual?" suggestion logic
└── Views/
    ├── RootView.swift                  TabView, hoisted selectedDate, deep-link watcher
    ├── TodayView.swift                 dashboard, smart-suggestion banner, P/C/F line
    │                                    on meal cards, water + suggestion undo handling
    ├── AddFoodView.swift               date-aware add tab, past-day banner
    ├── TrendsView.swift                Weight section (always-visible), Distribution
    │                                    by meal section, WeightEntriesSheet
    ├── BarcodeScannerSheet.swift       defaultMeal + defaultDate
    ├── PhotoLogSheet.swift             v1.8.5: multi-photo strip, low-confidence card
    ├── SearchSheet.swift               library swipe-add with Health-sync wiring
    ├── CSVExportSheet.swift            food + water + weight CSV via share sheet
    ├── NutritionBreakdownSheet.swift   respects selectedDate + pendingDeleteAt
    ├── NutrientGoalsSheet.swift        editable goals for the 14 secondary nutrients
    └── AuxViews.swift                  ConfirmFoodView, ManualEntrySheet, EditEntrySheet,
                                         SettingsView (Meal schedule, Reminders, Smart
                                         suggestions, Apple Health sections),
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
- Info tab → add `Privacy - Health Share Usage Description` and `Privacy - Health Update Usage Description`. Already wired as `INFOPLIST_KEY_*` build settings.

**Schema-change reinstalls.** Anytime fields are added to `@Model` classes, delete the app from your phone (long-press icon → Remove App → Delete App), then run fresh from Xcode. Always export CSV first via Settings → Data → Export. So far: v1.8 and v1.8.2 required reinstalls; v1.8.1, v1.8.3, v1.8.4, v1.8.5, v1.8.6, **v1.9** were schema-clean.

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
- **Search results from USDA include duplicates** — Foundation and SR Legacy datasets often both contain the same food.
- **SearchSheet quick-add on past day defaults to noon.** No time picker on quick-add; fix via EditEntrySheet's Time picker.
- **HealthKit "Show All Data" view shows nutrients individually, not grouped as a meal.** Food entries are saved as individual quantity samples (not HKCorrelation) because correlation types can't be authorized for writes. Per-nutrient summary screens (Calories Consumed / Protein / etc.) are unaffected.
- **HealthKit write failures are silent.** If a specific nutrient type was denied write permission, that sample is skipped. The remaining ones still write.
- **Smart-suggestion dismissal is in-memory only.** Tapping X hides for the rest of the view's lifetime. App relaunch resets. Acceptable for v1.
- **RelogSheet is dormant but maintained.** Has v1.7.1 defaultDate threading and v1.8.2 HealthSync wiring for consistency. Unreachable from UI.
- **Custom devil-fruit icon is AI-generated.** Original-art-enough for personal use; replace before any App Store submission.
