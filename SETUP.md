# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for three external calls (Open Food Facts for barcode lookups, Anthropic Claude for photo estimation, USDA FoodData Central for food name search).

Built collaboratively across multiple sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.7.1)

**Working features**

*Today tab — date-navigable meal-card dashboard*
- **Date navigation in the toolbar:** chevron `‹` / `›` step the view backward and forward by day. The forward chevron is disabled when viewing today (no future dates). The center title shows "Today," "Yesterday," or a formatted date like "Mon, May 4."
- **Tap the title** (with its small `‹›` indicator) → opens a date-picker sheet with a graphical calendar. Future dates are visually disabled. A **Today** button in the sheet's nav bar jumps you instantly back to today.
- **All cards reflect the selected day:** daily totals (calories/protein/carbs/fat), water tracking, meal-card subtotals, and Full breakdown all read from the selected day's entries.
- **Daily totals card** at the top: four equally-sized horizontal stat tiles (Calories / Protein / Carbs / Fat) with current totals against your daily goal.
- **Water tracking card**: progress bar, custom-amount entry with Log button (negatives supported), tap the count to set total directly, long-press the count to see and delete individual water entries for the selected day. Logging water on a past day timestamps the entry at noon of that day; logging on today uses the actual current time.
- **Meal-card dashboard:** four cards always visible — Breakfast, Lunch, Dinner, Snack — each showing the per-meal calorie subtotal **for the selected day**. Empty meals are ghosted, not hidden, so the layout stays consistent.
- **Tap any meal card → MealDetailSheet:** opens a focused sheet for that meal with the meal's totals at top, all entries for the selected day listed, swipe-left to soft-delete (with 5-second undo toast), tap any entry to edit all 19 nutrient fields, and a "**+ Add to {meal}**" section with four colored buttons (Search foods, Scan barcode, Photo estimate, Manual entry). Picking any entry point pre-tags both the meal context AND the selected date — so an entry added from yesterday's lunch card lands on yesterday's lunch.
- **"Full breakdown ›"** still accessible via the daily totals card → modal sheet showing all 19 nutrients in five sections with progress bars.
- Friendlier empty states when nothing's logged for a meal yet.
- Tab name remains "Today" because that's the default state on launch — you can navigate elsewhere, but the app always opens to today.

*Add tab — Most Used + Search + 3 inputs*
- **Always logs to today.** The Add tab is independent of Today's selectedDate — entries created here always go to the current day. To log to a past day, use the Today tab's meal-card "+ Add" buttons after navigating to that date.
- **Most Used** — top card on the Add tab (purple star icon). Tapping opens MostUsedSheet listing your top 10 library foods sorted by hybrid score (`useCount + recency * 5`, same algorithm as Search). Tapping any row → ConfirmFoodView so you can adjust grams before saving. Swipe-left removes a food from the library — with a 5-second undo toast at the bottom, same pattern as food entry deletes on Today. The greyed-out row stays visible during the undo window; tapping Undo restores it. Removing only deletes the LibraryFood record; your logged history is not affected.
- **Search foods** — unified search across the local food library (passively populated from every save path) and USDA FoodData Central. Library results stream instantly; USDA results follow after a 300ms debounce. Includes a "Branded foods" toggle for surfacing manufacturer-submitted entries when needed. Tapping any result lands on the Confirm screen.
- **Scan barcode** — Open Food Facts lookup pulls 19 nutrients where available.
- **Photo estimate** — opens the camera directly. Confirmation step ("Analyze") before any API call. Re-take button if you want a different shot. Claude vision API returns full nutrition with confidence rating.
- **Manual entry** — full form with Carbs detail / Fats detail / Cholesterol & electrolytes / Vitamins & minerals sections. Serving unit picker (g, ml, oz, serving, cup, tbsp, tsp, plus Custom…). Per-serving / total amount toggle at the top of the Serving section.

*Manual entry per-serving / totals mode*
- Segmented picker at the top of the Serving section: **"Per serving" / "Total amount."** Default is Per serving (legacy behavior, backward compatible).
- In **Per serving** mode, the form behaves exactly as before — fields are values for one serving, multiplied by the servings count on save.
- In **Total amount** mode, the "Servings" field becomes "Amount," and the macros section header changes to "Macros (totals)." A footer caption under the Serving section reminds you which mode is active. On save, the typed values are divided by the amount to derive per-serving values stored in the entry.
- Resolves the long-standing wart where typing `100 servings × 380 cal` stored 38,000 cal. Now you enter Amount=200, Unit=g, Calories=380 directly and it stores correctly.
- Storage layer is unchanged — Today, EditEntrySheet, CSV export, library upsert all see the same per-serving entries they always have. The toggle is a save-time transformation only.

*Trends tab*
- 4th tab between Add and Settings. Tab order: Today → Add → Trends → Settings (most-used → action → reflection → config). Icon: line chart trending up.
- **Range selector** at top: segmented picker for "7 days" / "30 days" / "Custom." Custom mode shows two date pickers with future-date prevention.
- **Daily averages for all 19 nutrients + water + calories,** organized into the same five sections as the breakdown sheet.
- **Progress bars** for the 5 main goals (calories, protein, carbs, fat, water) when goals are set. Other nutrients show numeric averages without bars.
- **Honest "based on N of M days" caption** below any row where the average doesn't cover the full range. Preserves the nil ≠ 0 invariant.
- **Empty state** when the range has no data: chart icon, "No data in this range," with a hint to expand the range.
- Pure read-only aggregation — no schema change, no app reinstall required.

*Time-derived meal defaults*
- When you open Manual Entry, Search results, Photo log, or any add flow from the **Add tab** (no explicit meal context), the meal picker is pre-set based on the current time:
  - 6:00–9:59 → Breakfast
  - 10:00–11:59 → Snack
  - 12:00–13:59 → Lunch
  - 14:00–16:59 → Snack
  - 17:00–19:59 → Dinner
  - 20:00–5:59 → Snack (late)
- When you open the same flows from a **meal card** ("Add to lunch"), the explicit meal context wins and the time-of-day default is ignored.

*Late-night snack confirmation*
- Saving a food classified as "snack" inside the configured late-night window triggers a confirmation alert: *"Late-night snack? It's getting late..."* with two buttons: "Cancel" or "Log it anyway."
- **Configurable via Settings:** toggle on/off, plus Start and End hour pickers (12-hour format display, 0–23 internal). Defaults are 8pm–6am, enabled.
- Window can wrap midnight (8pm–6am, the default) or stay same-day (e.g. 9am–11am for an unusual schedule). Math handles both cases.
- Wired into all four save paths: ConfirmFoodView (search/barcode), ManualEntrySheet, RelogSheet (dormant but still functional), and PhotoLogSheet — they all call `MealTimeHelper.shouldWarnAboutLateSnack(meal:)` which reads the user's config from UserDefaults.
- Settings persist via @AppStorage — changes apply immediately and survive force-quit. No schema change.

*Edit any logged entry*
- Tap any entry on a meal card's detail sheet → opens an EditEntrySheet that mirrors Manual Entry but pre-populated with the existing entry's values.
- All 19 nutrient fields editable, plus name, brand, servings, unit (with same Custom… support), and meal.
- Numeric fields use select-all-on-focus.
- Save mutates the existing FoodEntry in place — SwiftData persists automatically.
- Editing also bumps the LibraryFood record's `useCount` (and creates one if none exists).
- **EditEntrySheet preserves the entry's `loggedAt` date.** Editing yesterday's entry doesn't move it to today. To move an entry to a different day, delete and re-log on the desired day.
- Note: EditEntrySheet does NOT have the per-serving/totals toggle. Edits are always per-serving.

*Confirm screen (barcode + search + Most Used results)*
- Top-right Save button matching the rest of the app.
- Tap into the grams field → existing value highlights, ready to be replaced.
- Done button on the keyboard accessory bar.
- Adjusting grams scales every nutrient in real time.
- Meal picker respects pre-tagged context if set, otherwise defaults to time-of-day meal.
- When opened from a past-day meal card, the entry is timestamped at noon of that day on save.

*Settings*
- **Save button in top-right of nav bar** (matches Manual Entry / Edit Entry pattern).
- Daily goals for calories, protein, carbs, fat, water (5 main goals).
- **More nutrient goals** sheet: editable targets for all 14 remaining nutrients (fiber, sugar, sat/poly/mono/trans fats, cholesterol, sodium, potassium, vitamins A/C/D, calcium, iron, magnesium). Blank fields = no daily target, no progress bar shown.
- **Late-night snack alert**: toggle + Start/End hour pickers, dynamic footer showing the active window. Auto-saves on change.
- **Data section:**
  - **Export data** — pick a date range (default last 30 days), exports two CSVs (food + water) via the iOS share sheet. Nil nutrients render as empty cells, never zero. Soft-deleted entries pending undo are excluded.
  - **Reset food library** — destructive button with confirmation alert.
- **API keys section:** compact rows showing "Set" (green) or "Not set" (gray) status, tappable to open a focused edit sheet (Anthropic key sheet, USDA key sheet — each with SecureField, linkified footer, Save / Clear buttons, auto-dismiss on save).

*App icon*
- Custom devil-fruit-themed icon (purple swirly fruit on lavender background, generated via Gemini).

*Throughout*
- Haptic feedback on logging, saving, and destructive actions (success notification, light tap, medium tap).
- Save/Log buttons dismiss the keyboard.
- Done button on numeric keypad in long forms.
- Numeric fields select-all-on-focus on Manual Entry, Edit Entry, Confirm, and Goals sheets.
- Numbers round cleanly: "3" not "3.0", "<0.1" for tiny values, "2.5" for fractional.

**Tracked nutrients (19 fields + water)**
Calories, Protein, Carbs, Fiber, Sugar, Total Fat, Saturated, Polyunsaturated, Monounsaturated, Trans, Cholesterol, Sodium, Potassium, Vitamin A, Vitamin C, Vitamin D, Calcium, Iron, Magnesium.

Critical design choice: optional fields use `Double?`. Empty form fields stay nil. Nil ≠ 0 anywhere — the breakdown displays "–" for unknown values rather than misleading zeros. CSV exports render nil as empty cells. Trends rows say "based on N of M days" so partial-coverage averages stay honest.

**Tech stack**
- iOS 18+ (deploys to iOS 26.4 on Mike's iPhone 17 Pro Max)
- Xcode 26.4
- SwiftUI + SwiftData
- VisionKit `DataScannerViewController` for barcode scanning
- `UIImagePickerController` (wrapped in SwiftUI) for camera capture
- Open Food Facts API (free, no key) for product lookup
- Anthropic Messages API (`claude-sonnet-4-6`) for photo nutrition estimation
- USDA FoodData Central API (free, requires personal key from api.data.gov) for food name search
- CryptoKit SHA256 hashing of resized image pixel data for photo cache keys
- Keychain for both Anthropic and USDA API key storage (parameterized via `KeychainStore.Key` enum)
- @AppStorage / UserDefaults for late-night-warning configuration — scalar prefs, no SwiftData ceremony, no schema change
- Git, committed phase by phase via terminal (Xcode's commit UI is unreliable for this project)

**Date navigation architecture (v1.7.1)**
- TodayView holds a `selectedDate: Date` state, defaulting to `Calendar.current.startOfDay(for: .now)` on launch.
- All date filters use `Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate)` instead of the old `isDateInToday`.
- A `timestampForSave()` helper returns `.now` when `selectedDate` is today (preserves real time-of-day) and noon-of-selectedDate otherwise (entries only need to land on the right calendar day; meal-type field handles the slot).
- A `defaultDate: Date?` parameter is threaded alongside `defaultMeal: String?` through ConfirmFoodView, ManualEntrySheet, BarcodeScannerSheet, SearchSheet, PhotoLogSheet. All five sheets default to `nil` for backward compatibility — `nil` falls through to `.now` and existing call sites (Add tab) work unchanged.
- Food save paths use mutation (`entry.loggedAt = defaultDate`) rather than passing `loggedAt:` in the FoodEntry init. This avoids coupling to FoodEntry's init parameter order.
- The chevron-forward button is disabled when `Calendar.current.isDateInToday(selectedDate)`. The date picker sheet uses `in: ...Calendar.current.startOfDay(for: .now)` to block future dates.
- MealDetailSheet now accepts a `selectedDate` parameter and uses it for both filtering displayed entries and computing the `saveDate` it passes to the four input sheets.

**Search & food library architecture**
- `LibraryFood` `@Model` class — one record per unique food name+brand combo the user has ever logged.
- `LibraryFoodUpsert.upsert(from:in:)` helper called from every save path (manual, barcode, photo, search, edit) — silently maintains the library.
- Hybrid storage: per-100g if the original log was in grams (manual-style "g" unit with servings ≥ 10, OR barcode-style "<N>g" unit), otherwise per-serving with the original unit.
- `LibraryService.search(_:in:)` — substring + case-insensitive match across name and brand, scored by `useCount + recency_boost`. Returns top 25.
- `USDAService.search(_:includeBranded:)` — async query against FoodData Central. Defaults to Foundation + SR Legacy + Survey (FNDDS); branded foods toggleable. Maps nutrient IDs → per-100g values that slot directly into `ConfirmFoodView.Prefill`. Force-encodes parens (`(` → `%28`, `)` → `%29`) because USDA's nginx fronting layer rejects raw parens in query strings.
- Search UI uses a 300ms debounce + UUID-keyed cancellation token so fast typing doesn't spam the API and stale responses can't overwrite newer ones.
- **Most Used** uses the same hybrid-score sort as Search. Removal uses transient view-state for undo (no `pendingDeleteAt` field needed on LibraryFood, no schema change).

**Meal-time logic**
- `MealTimeHelper` enum with three pure public functions:
  - `mealType(at:)` — maps a Date's hour to "breakfast" / "lunch" / "dinner" / "snack". Schedule is fixed (not yet user-configurable).
  - `isLateNight(at:)` — true when current hour falls inside the user's configured window. Reads `lateNightWarningStartHour` and `lateNightWarningEndHour` from UserDefaults, falls back to 20/6 if unset. Handles wrap-around.
  - `shouldWarnAboutLateSnack(meal:at:)` — returns true only when warning is enabled (UserDefaults `lateNightWarningEnabled`, defaults true), the meal is "snack," AND it's late-night by the user's window.

**Photo logging cost optimization**
- Sonnet, not Opus — ~5x cheaper per call with no perceptible accuracy loss for food photos.
- **Image-hash cache** (CachedPhotoEstimate model) — re-logging the same photo returns instantly with no API call. Hashes the resized image's raw pixel data (not JPEG bytes) so the same photo picked twice always matches.
- **Confirmation step** — "Analyze" button after the camera captures, so accidental snaps don't burn API calls.
- **Capped max_tokens** (1024) — guards against runaway responses.
- **Aggressive image compression** (768px / 0.6 quality) — keeps input cost down.

Effect: photo logging that was costing roughly $0.01–0.02 per estimate on Opus is now closer to $0.001–0.002 on Sonnet, and re-logs are free. Search is fully free (USDA's API has no cost; library is local).

**Project structure**
```
FoodJournal/
├── FoodJournalApp.swift              entry point, SwiftData container (6 models)
├── Assets.xcassets
│   └── AppIcon.appiconset             custom devil-fruit icon (Gemini-generated PNG)
├── Models/
│   └── Models.swift                   FoodEntry (+ pendingDeleteAt), UserGoals,
│                                       CachedFood, WaterEntry, CachedPhotoEstimate,
│                                       LibraryFood, LibraryFoodUpsert helper, FoodFormat enum
├── Services/
│   ├── OpenFoodFactsService.swift     barcode → product lookup (full nutrition)
│   ├── ClaudeVisionService.swift      photo → nutrition estimate; pixel-hash helper
│   ├── USDAService.swift              food name → search hits (per-100g, normalized)
│   ├── LibraryService.swift           local library substring search + recency scoring
│   ├── MealTimeHelper.swift           reads UserDefaults for late-night config
│   └── KeychainStore.swift            parameterized key storage (anthropic + usda)
└── Views/
    ├── RootView.swift                 tab bar (Today / Add / Trends / Settings)
    ├── TodayView.swift                v1.7.1: date-navigable; selectedDate state, chevron
    │                                   toolbar, date-picker sheet, MealDetailSheet accepts
    │                                   and threads selectedDate. timestampForSave() helper.
    ├── AddFoodView.swift              Most Used with undo + 4 input cards, MostUsedSheet
    ├── TrendsView.swift               range picker + per-section averages
    ├── BarcodeScannerSheet.swift      v1.7.1: accepts defaultDate alongside defaultMeal
    ├── PhotoLogSheet.swift            v1.7.1: accepts defaultDate; saveEntry mutates loggedAt
    ├── SearchSheet.swift              v1.7.1: accepts defaultDate; passes through to Confirm
    ├── CSVExportSheet.swift           date range picker + dual-CSV export via share sheet
    ├── NutritionBreakdownSheet.swift  full breakdown of all 19 nutrients
    ├── NutrientGoalsSheet.swift       editable goals for the 14 secondary nutrients
    └── AuxViews.swift                 v1.7.1: ConfirmFoodView and ManualEntrySheet now accept
                                        defaultDate and mutate entry.loggedAt before insert.
                                        Also: SettingsView, AnthropicKeySheet, USDAKeySheet,
                                        RelogSheet (dormant), EditEntrySheet, dismissKeyboard,
                                        SelectAllOnFocus modifier, Haptic helper, CameraPicker
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R. First-time setup is documented in earlier conversation history (camera permission, developer mode on phone, trust certificate).

To use photo logging, paste an Anthropic API key in Settings → API keys → Anthropic API key (`sk-ant-...`). Get one at console.anthropic.com — needs at least a few dollars of credit.

To use food search, paste a USDA API key in Settings → API keys → USDA API key. Get one at api.data.gov/signup — free, takes 30 seconds, key arrives by email. Without it, library-only search still works (no USDA fallback).

When the SwiftData schema changes (which means anytime fields are added to any `@Model` class), delete the app from your phone first (long-press icon → Remove App → Delete App), then run from Xcode. Migration from the previous schema isn't set up — fresh install is the simplest path. **Always export your data first via Settings → Data → Export** if you'll miss the historical entries. **v1.7 and v1.7.1 introduced no schema changes**, so the upgrades from v1.6 onward have been non-destructive.

**Committing changes:** use terminal, not Xcode's UI. The Xcode commit UI is unreliable for this project. Workflow:
```
cd ~/Desktop/FoodJournal/FoodJournal
git add .
git commit -m "what changed"
git log --oneline -5
```

## Known issues / quirks

- **Most Used dedup is by name+brand** — if "apple" got logged once at 95 Calories and once at 80 Calories, they're treated as one library entry with the most recent values winning. Probably fine in practice. Removing from Most Used deletes the library record only, not the underlying journal history. Reversible via 5-second undo.
- **Open Food Facts unit conversions** — sodium/calcium/iron/magnesium/potassium are converted from grams to mg, vitamins A/D from g to µg, vitamin C from g to mg. These conversions are right for ~95% of products. If a product reads dramatically wrong, it might be storing data in an unusual unit and we'd need a one-off fix.
- **No error UI for network failures on barcode scan** — Open Food Facts timeouts surface as "not found" which is misleading.
- **Undo doesn't apply to water entries.** Adding undo to WaterEntriesSheet requires a `pendingDeleteAt` schema change on `WaterEntry` — bundled into the v1.8 schema-change session.
- **Force-quitting the app while the undo toast is showing** commits the pending delete on next launch. Acceptable since it's a 5-second window and crashes are rare.
- **Manual entry per-serving misuse is resolved** by the totals-mode toggle. Old entries logged before v1.7 with the 38,000-calorie pattern are still in the database — open them via Today → meal card → tap entry → fix in EditEntrySheet, or delete and re-log.
- **EditEntrySheet has no totals toggle and no date picker** — by design. Existing entries are already in per-serving form, and editing a date during normal cleanup is rarely needed. To "edit a totals-mode entry," delete and re-log via Manual entry in totals mode. To move an entry to a different day, delete and re-log on that day via Today's date navigation.
- **Library per-serving fallback:** when a LibraryFood was originally logged with a non-gram unit (cup, tbsp, "burrito"), picking it from search or Most Used lands you on the Confirm screen with grams = 100. Macros are technically per-serving but presented "for 100g." Real-world impact small since most logs are in grams.
- **Search results from USDA include duplicates** — Foundation and SR Legacy datasets often both contain the same food (e.g. two "Broccoli, raw" entries). The data-type pill colors them differently.
- **Time-derived defaults don't account for shift work or unusual schedules** — if you're a night-shift worker eating "breakfast" at 6pm, the picker will still suggest Dinner. Custom meal-time schedules are bundled into the v1.8 schema-change session.
- **Late-night warning is per-save, not per-session** — every snack you log inside the configured window triggers the alert independently. By design (the friction is the feature). Disable-able entirely or window-adjustable via Settings.
- **Past-day entries are timestamped at noon of that day.** This means individual entries logged for past days won't show realistic time-of-day in WaterEntriesSheet ("12:00 PM"). Doesn't affect totals or daily display since meal grouping is by `mealType` field, not hour. Could be addressed by adding a time picker to past-day add flows in a future session.
- **Add tab always logs to today**, even when you're viewing a past day in Today. By design — the Add tab is the "log something now" path. Use the Today tab's meal-card "+ Add" buttons after navigating to a past day instead.
- **RelogSheet is dormant but still in the codebase** — was the previous Recents flow. Now unreachable from the Add tab since Most Used replaced it. Does NOT have the v1.7.1 `defaultDate` parameter wired in (would be a 30-second edit if revived).
- **Custom devil-fruit icon is AI-generated.** Original-art-enough for personal use but should be replaced before any App Store submission.
