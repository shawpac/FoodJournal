# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for two API calls (Open Food Facts for barcode lookups, Claude for photo estimation).

Built collaboratively across multiple sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.4)

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
- **Scan barcode** — Open Food Facts lookup pulls 19 nutrients where available
- **Photo estimate** — opens the camera directly, snap the meal in front of you. Confirmation step ("Analyze") before any API call. Re-take button if you want a different shot. Claude vision API returns full nutrition with confidence rating; honestly returns nil for vitamins/minerals it can't see.
- **Manual entry** — full form with Carbs detail / Fats detail / Cholesterol & electrolytes / Vitamins & minerals sections. Serving unit is a picker: grams (g), milliliters (ml), ounces (oz), serving, cup, tbsp, tsp, plus a Custom… option that opens a text field for things like "1 burrito"

*Edit any logged entry*
- Tap any entry on Today → opens an EditEntrySheet that mirrors Manual Entry but pre-populated with the existing entry's values
- All 19 nutrient fields editable, plus name, brand, servings, unit (with same Custom… support), and meal
- Numeric fields use select-all-on-focus: tapping a field highlights existing text so the next keystroke replaces it cleanly
- Save mutates the existing FoodEntry in place — SwiftData persists automatically

*Settings*
- Daily goals for calories, protein, carbs, fat, water (5 main goals)
- **More nutrient goals** sheet: editable targets for all 14 remaining nutrients (fiber, sugar, sat/poly/mono/trans fats, cholesterol, sodium, potassium, vitamins A/C/D, calcium, iron, magnesium). Blank fields = no daily target, no progress bar shown.
- Anthropic API key stored in Keychain

*Throughout*
- Haptic feedback on logging, saving, and destructive actions (success notification, light tap, medium tap)
- Save/Log buttons dismiss the keyboard
- Done button on numeric keypad in long forms
- Numeric fields select-all-on-focus on Manual Entry, Edit Entry, Re-log, and Goals sheets
- Numbers round cleanly: "3" not "3.0", "<0.1" for tiny values, "2.5" for fractional

**Tracked nutrients (19 fields + water)**
Calories, Protein, Carbs, Fiber, Sugar, Total Fat, Saturated, Polyunsaturated, Monounsaturated, Trans, Cholesterol, Sodium, Potassium, Vitamin A, Vitamin C, Vitamin D, Calcium, Iron, Magnesium.

Critical design choice: optional fields use `Double?`. Empty form fields stay nil. Nil ≠ 0 anywhere — the breakdown displays "–" for unknown values rather than misleading zeros. This matters for sums (a vitamin total only counts entries that have that vitamin set) and will matter even more for averages over time periods.

**Tech stack**
- iOS 18+ (deploys to iOS 26.4 on Mike's iPhone 17 Pro Max)
- Xcode 26.4
- SwiftUI + SwiftData
- VisionKit `DataScannerViewController` for barcode scanning
- `UIImagePickerController` (wrapped in SwiftUI) for camera capture
- Open Food Facts API (free, no key) for product lookup
- Anthropic Messages API (`claude-sonnet-4-6`) for photo nutrition estimation
- CryptoKit SHA256 hashing of resized image pixel data for photo cache keys
- Keychain for API key storage
- Git, committed phase by phase

**Photo logging cost optimization**
The photo flow is engineered for low API cost:
- **Sonnet, not Opus** — ~5x cheaper per call with no perceptible accuracy loss for food photos
- **Image-hash cache** (CachedPhotoEstimate model) — re-logging the same photo returns instantly with no API call. Hashes the resized image's raw pixel data (not JPEG bytes) so the same photo picked twice always matches.
- **Confirmation step** — "Analyze" button after the camera captures, so accidental snaps don't burn API calls
- **Capped max_tokens** (1024) — guards against runaway responses
- **Aggressive image compression** (768px / 0.6 quality) — keeps input cost down

Effect: photo logging that was costing roughly $0.01–0.02 per estimate on Opus is now closer to $0.001–0.002 on Sonnet, and re-logs are free.

**Project structure**
```
FoodJournal/
├── FoodJournalApp.swift              entry point, SwiftData container
├── Assets.xcassets
├── Models/
│   └── Models.swift                  FoodEntry (+ pendingDeleteAt), UserGoals,
│                                      CachedFood, WaterEntry, CachedPhotoEstimate,
│                                      FoodFormat enum
├── Services/
│   ├── OpenFoodFactsService.swift    barcode → product lookup (full nutrition)
│   ├── ClaudeVisionService.swift     photo → nutrition estimate; pixel-hash helper
│   └── KeychainStore.swift           API key storage
└── Views/
    ├── RootView.swift                tab bar
    ├── TodayView.swift               summary, macros, water, meal-grouped entries,
    │                                  undo-delete toast, WaterEntriesSheet, EntryRow
    ├── AddFoodView.swift             recents (with timestamps + swipe-delete) + 3 input cards
    ├── BarcodeScannerSheet.swift
    ├── PhotoLogSheet.swift           camera capture + Analyze confirmation + cache check
    ├── NutritionBreakdownSheet.swift full breakdown of all 19 nutrients
    ├── NutrientGoalsSheet.swift      editable goals for the 14 secondary nutrients
    └── AuxViews.swift                ConfirmFoodView, ManualEntrySheet, SettingsView,
                                       RelogSheet, EditEntrySheet, dismissKeyboard,
                                       SelectAllOnFocus modifier, Haptic helper,
                                       CameraPicker UIViewControllerRepresentable
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R. First-time setup is documented in earlier conversation history (camera permission, developer mode on phone, trust certificate).

To use photo logging, paste an Anthropic API key in Settings (`sk-ant-...`). Get one at console.anthropic.com — needs at least a few dollars of credit. Photo logging now costs roughly $0.001–0.002 per estimate, and zero for re-logs that hit the cache.

When the SwiftData schema changes (which means anytime fields are added to FoodEntry or UserGoals), delete the app from your phone first (long-press icon → Remove App → Delete App), then run from Xcode. Migration from the previous schema isn't set up — fresh install is the simplest path.

## Known issues / quirks

- **Recents dedup is by name+brand** — if "apple" got logged once at 95 Calories and once at 80 Calories, only the most recent shows. Probably fine in practice. Removing from Recents deletes all matching history (intentional — otherwise the older copy would just resurrect).
- **Open Food Facts unit conversions** — sodium/calcium/iron/magnesium/potassium are converted from grams to mg, vitamins A/D from g to µg, vitamin C from g to mg. These conversions are right for ~95% of products. If a product reads dramatically wrong, it might be storing data in an unusual unit and we'd need a one-off fix.
- **No error UI for network failures on barcode scan** — Open Food Facts timeouts surface as "not found" which is misleading.
- **Undo only applies to food entry deletes**, not water entries (in WaterEntriesSheet) or Recents removal (in AddFoodView). Adding undo to those is straightforward but wasn't done in the v1.4 cleanup pass.
- **Force-quitting the app while the undo toast is showing** commits the pending delete on next launch. Acceptable since it's a 5-second window and crashes are rare.
