# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for three external calls (Open Food Facts for barcode lookups, Anthropic Claude for photo estimation, USDA FoodData Central for food name search).

Built collaboratively across multiple sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.5)

**Working features**

*Today tab*
- Calorie ring shows "of X Calories"
- Three macro pills (protein / carbs / fat) with progress bars
- Water tracking card: progress bar, custom-amount entry with Log button (negatives supported), tap the count to set total directly, long-press the count to see and delete individual water entries
- Tap "Full breakdown ›" → modal sheet showing all 19 nutrients in five sections with progress bars
- **Meal grouping:** entries are grouped into Breakfast / Lunch / Dinner / Snacks cards with per-meal calorie subtotals. Empty meals hide automatically. Order is always Breakfast→Lunch→Dinner→Snacks regardless of log time.
- Tap any logged entry → opens Edit sheet with all 19 nutrient fields editable
- Swipe-left on any logged entry → soft-delete with **5-second undo toast** at the bottom of the screen. Rapid-fire deletes group into one toast; tapping Undo within the window restores everything pending.
- Friendlier empty state when nothing's logged today

*Add tab*
- **Recents** — top 10 unique foods deduped by name+brand. Each row shows brand • servings • relative timestamp ("3h ago"). Swipe-left to remove from Recents (deletes all history matching that name+brand).
- **Search foods** *(new in v1.5)* — unified search across the local food library (passively populated from every save path) and USDA FoodData Central. Library results stream instantly; USDA results follow after a 300ms debounce. Includes a "Branded foods" toggle for surfacing manufacturer-submitted entries when needed. Tapping any result lands on the Confirm screen, which behaves like a barcode confirm.
- **Scan barcode** — Open Food Facts lookup pulls 19 nutrients where available
- **Photo estimate** — opens the camera directly, snap the meal in front of you. Confirmation step ("Analyze") before any API call. Re-take button if you want a different shot. Claude vision API returns full nutrition with confidence rating; honestly returns nil for vitamins/minerals it can't see.
- **Manual entry** — full form with Carbs detail / Fats detail / Cholesterol & electrolytes / Vitamins & minerals sections. Serving unit is a picker: grams (g), milliliters (ml), ounces (oz), serving, cup, tbsp, tsp, plus a Custom… option that opens a text field for things like "1 burrito"

*Edit any logged entry*
- Tap any entry on Today → opens an EditEntrySheet that mirrors Manual Entry but pre-populated with the existing entry's values
- All 19 nutrient fields editable, plus name, brand, servings, unit (with same Custom… support), and meal
- Numeric fields use select-all-on-focus: tapping a field highlights existing text so the next keystroke replaces it cleanly
- Save mutates the existing FoodEntry in place — SwiftData persists automatically
- Editing also bumps the LibraryFood record's `useCount` (and creates one if none exists)

*Confirm screen (barcode + search results)*
- Top-right Save button matching the rest of the app
- Tap into the grams field → existing value highlights, ready to be replaced
- Done button on the keyboard accessory bar
- Adjusting grams scales every nutrient in real time

*Settings*
- **Save button in top-right of nav bar** (matches Manual Entry / Edit Entry pattern)
- Daily goals for calories, protein, carbs, fat, water (5 main goals)
- **More nutrient goals** sheet: editable targets for all 14 remaining nutrients (fiber, sugar, sat/poly/mono/trans fats, cholesterol, sodium, potassium, vitamins A/C/D, calcium, iron, magnesium). Blank fields = no daily target, no progress bar shown.
- **Data section:**
  - **Export data** — pick a date range (default last 30 days), exports two CSVs (food + water) via the iOS share sheet. Nil nutrients render as empty cells, never zero. Soft-deleted entries pending undo are excluded.
  - **Reset food library** *(new in v1.5)* — destructive button with confirmation alert ("This will erase all N library records. Your existing journal entries are not affected. The library will refill itself as you log foods.")
- **API keys section** *(new in v1.5)* — compact rows showing "Set" (green) or "Not set" (gray) status, tappable to open a focused edit sheet:
  - **Anthropic API key sheet** — SecureField, footer with tappable link to console.anthropic.com, Save / Clear key buttons, auto-dismiss on save
  - **USDA API key sheet** — SecureField, footer with tappable link to api.data.gov/signup, Save / Clear key buttons, auto-dismiss on save
- Each sheet shows transient confirmation ("✓ Saved 40 chars") before auto-closing

*App icon*
- Custom devil-fruit-themed icon (purple swirly fruit on lavender background, generated via Gemini and dropped into Assets.xcassets / AppIcon)

*Throughout*
- Haptic feedback on logging, saving, and destructive actions (success notification, light tap, medium tap)
- Save/Log buttons dismiss the keyboard
- Done button on numeric keypad in long forms
- Numeric fields select-all-on-focus on Manual Entry, Edit Entry, Confirm, Re-log, and Goals sheets
- Numbers round cleanly: "3" not "3.0", "<0.1" for tiny values, "2.5" for fractional

**Tracked nutrients (19 fields + water)**
Calories, Protein, Carbs, Fiber, Sugar, Total Fat, Saturated, Polyunsaturated, Monounsaturated, Trans, Cholesterol, Sodium, Potassium, Vitamin A, Vitamin C, Vitamin D, Calcium, Iron, Magnesium.

Critical design choice: optional fields use `Double?`. Empty form fields stay nil. Nil ≠ 0 anywhere — the breakdown displays "–" for unknown values rather than misleading zeros. CSV exports render nil as empty cells. This matters for sums (a vitamin total only counts entries that have that vitamin set) and matters even more for averages over time periods.

**Tech stack**
- iOS 18+ (deploys to iOS 26.4 on Mike's iPhone 17 Pro Max)
- Xcode 26.4
- SwiftUI + SwiftData
- VisionKit `DataScannerViewController` for barcode scanning
- `UIImagePickerController` (wrapped in SwiftUI) for camera capture
- Open Food Facts API (free, no key) for product lookup
- Anthropic Messages API (`claude-sonnet-4-6`) for photo nutrition estimation
- **USDA FoodData Central API** (free, requires personal key from api.data.gov) for food name search
- CryptoKit SHA256 hashing of resized image pixel data for photo cache keys
- Keychain for both Anthropic and USDA API key storage (parameterized via `KeychainStore.Key` enum)
- Git, committed phase by phase via terminal (Xcode's commit UI is unreliable for this project)

**Search & food library architecture (v1.5)**
- New `LibraryFood` `@Model` class — one record per unique food name+brand combo the user has ever logged
- New `LibraryFoodUpsert.upsert(from:in:)` helper called from every save path (manual, barcode, photo, search, re-log, edit) — silently maintains the library
- Hybrid storage: per-100g if the original log was in grams (manual-style "g" unit with servings >= 10, OR barcode-style "<N>g" unit), otherwise per-serving with the original unit. The 10g threshold filters out misclassified low-servings logs.
- New `LibraryService.search(_:in:)` — substring + case-insensitive match across name and brand, scored by `useCount + recency_boost`. Returns top 25.
- New `USDAService.search(_:includeBranded:)` — async query against FoodData Central. Defaults to Foundation + SR Legacy + Survey (FNDDS); branded foods toggleable. Maps nutrient IDs → per-100g values that slot directly into `ConfirmFoodView.Prefill`. Force-encodes parens (`(` → `%28`, `)` → `%29`) because USDA's nginx fronting layer rejects raw parens in query strings.
- Search UI uses a 300ms debounce + UUID-keyed cancellation token so fast typing doesn't spam the API and stale responses can't overwrite newer ones.

**Photo logging cost optimization**
The photo flow remains engineered for low API cost:
- Sonnet, not Opus — ~5x cheaper per call with no perceptible accuracy loss for food photos
- **Image-hash cache** (CachedPhotoEstimate model) — re-logging the same photo returns instantly with no API call. Hashes the resized image's raw pixel data (not JPEG bytes) so the same photo picked twice always matches.
- **Confirmation step** — "Analyze" button after the camera captures, so accidental snaps don't burn API calls
- **Capped max_tokens** (1024) — guards against runaway responses
- **Aggressive image compression** (768px / 0.6 quality) — keeps input cost down

Effect: photo logging that was costing roughly $0.01–0.02 per estimate on Opus is now closer to $0.001–0.002 on Sonnet, and re-logs are free. Search is fully free (USDA's API has no cost; library is local).

**Project structure**
```
FoodJournal/
├── FoodJournalApp.swift              entry point, SwiftData container (now includes LibraryFood)
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
│   └── KeychainStore.swift            parameterized key storage (anthropic + usda)
└── Views/
    ├── RootView.swift                 tab bar
    ├── TodayView.swift                summary, macros, water, meal-grouped entries,
    │                                   undo-delete toast, WaterEntriesSheet, EntryRow
    ├── AddFoodView.swift              recents (timestamps + swipe-delete) + 4 input cards
    ├── BarcodeScannerSheet.swift
    ├── PhotoLogSheet.swift             camera capture + Analyze confirmation + cache check
    ├── SearchSheet.swift               unified library + USDA search with debounce
    ├── CSVExportSheet.swift            date range picker + dual-CSV export via share sheet
    ├── NutritionBreakdownSheet.swift   full breakdown of all 19 nutrients
    ├── NutrientGoalsSheet.swift        editable goals for the 14 secondary nutrients
    └── AuxViews.swift                  ConfirmFoodView, ManualEntrySheet, SettingsView,
                                        AnthropicKeySheet, USDAKeySheet, RelogSheet,
                                        EditEntrySheet, dismissKeyboard, SelectAllOnFocus
                                        modifier, Haptic helper, CameraPicker
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R. First-time setup is documented in earlier conversation history (camera permission, developer mode on phone, trust certificate).

To use photo logging, paste an Anthropic API key in Settings → API keys → Anthropic API key (`sk-ant-...`). Get one at console.anthropic.com — needs at least a few dollars of credit.

To use food search, paste a USDA API key in Settings → API keys → USDA API key. Get one at api.data.gov/signup — free, takes 30 seconds, key arrives by email. Without it, library-only search still works (no USDA fallback).

When the SwiftData schema changes (which means anytime fields are added to any `@Model` class), delete the app from your phone first (long-press icon → Remove App → Delete App), then run from Xcode. Migration from the previous schema isn't set up — fresh install is the simplest path. **Always export your data first via Settings → Data → Export** if you'll miss the historical entries.

**Committing changes:** use terminal, not Xcode's UI. The Xcode commit UI is unreliable for this project. Workflow:
```
cd ~/Desktop/FoodJournal/FoodJournal
git add .
git commit -m "what changed"
git log --oneline -5
```

## Known issues / quirks

- **Recents dedup is by name+brand** — if "apple" got logged once at 95 Calories and once at 80 Calories, only the most recent shows. Probably fine in practice. Removing from Recents deletes all matching history (intentional — otherwise the older copy would just resurrect).
- **Open Food Facts unit conversions** — sodium/calcium/iron/magnesium/potassium are converted from grams to mg, vitamins A/D from g to µg, vitamin C from g to mg. These conversions are right for ~95% of products. If a product reads dramatically wrong, it might be storing data in an unusual unit and we'd need a one-off fix.
- **No error UI for network failures on barcode scan** — Open Food Facts timeouts surface as "not found" which is misleading.
- **Undo only applies to food entry deletes**, not water entries (in WaterEntriesSheet) or Recents removal (in AddFoodView). Adding undo to those is straightforward but wasn't done in v1.4 or v1.5.
- **Force-quitting the app while the undo toast is showing** commits the pending delete on next launch. Acceptable since it's a 5-second window and crashes are rare.
- **Manual entry per-serving expectation:** when you type "100 servings of g, 380 calories" intending "100g of oatmeal at 380 cal total," the app records 38,000 calories because the Calories field is per-serving, not total. The intended workflow for that food is `servings=1, unit="100g" (custom), calories=380`. Once Search is in regular use this confusion mostly goes away. Documented for now, may revisit.
- **Library per-serving fallback:** when a LibraryFood was originally logged with a non-gram unit (cup, tbsp, "burrito"), picking it from search lands you on the Confirm screen with grams = 100. Macros are technically per-serving but presented "for 100g." Real-world impact small since most logs are in grams.
- **Search results from USDA include duplicates** — Foundation and SR Legacy datasets often both contain the same food (e.g. two "Broccoli, raw" entries). The data-type pill colors them differently so you can tell which is which. Pick whichever feels right.
- **Custom devil-fruit icon is AI-generated.** Original-art-enough for personal use but should be replaced before any App Store submission.
