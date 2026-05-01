# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for two API calls (Open Food Facts for barcode lookups, Claude for photo estimation).

Built collaboratively across multiple sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.3)

**Working features**

*Today tab*
- Calorie ring shows "of X Calories" (no more "kcal")
- Three macro pills (protein / carbs / fat) with progress bars
- Water tracking card: progress bar, custom-amount entry with Log button (negatives supported), tap the count to set total directly, long-press the count to see and delete individual water entries
- Tap "Full breakdown ›" → modal sheet showing all 19 nutrients in five sections with progress bars
- **Meal grouping:** entries are grouped into Breakfast / Lunch / Dinner / Snacks cards with per-meal calorie subtotals. Empty meals hide automatically. Order is always Breakfast→Lunch→Dinner→Snacks regardless of log time.
- Tap any logged entry → opens Edit sheet with all 19 nutrient fields editable
- Swipe-left on any logged entry → Delete

*Add tab*
- **Recents** — top 10 unique foods deduped by name+brand. Each row shows brand • servings • relative timestamp ("3h ago"). Swipe-left to remove from Recents (deletes all history matching that name+brand).
- **Scan barcode** — Open Food Facts lookup pulls 19 nutrients where available
- **Photo estimate** — Claude vision API (claude-opus-4-7) returns nutrition with confidence rating; honestly returns nil for vitamins/minerals it can't see
- **Manual entry** — full form with Carbs detail / Fats detail / Cholesterol & electrolytes / Vitamins & minerals sections. Serving unit is a picker: grams (g), milliliters (ml), ounces (oz), serving, cup, tbsp, tsp, plus a Custom… option that opens a text field for things like "1 burrito"

*Edit any logged entry*
- Tap any entry on Today → opens an EditEntrySheet that mirrors Manual Entry but pre-populated with the existing entry's values
- All 19 nutrient fields editable, plus name, brand, servings, unit (with same Custom… support), and meal
- Numeric fields use select-all-on-focus: tapping a field highlights existing text so the next keystroke replaces it cleanly
- Save mutates the existing FoodEntry in place — SwiftData persists automatically

*Settings*
- Daily goals for calories, protein, carbs, fat, water (additional 14 nutrient goals stored with sensible defaults but not yet editable from UI)
- Anthropic API key stored in Keychain

*Throughout*
- Save/Log buttons dismiss the keyboard
- Done button on numeric keypad in long forms
- Numeric fields select-all-on-focus on Manual Entry, Edit Entry, and Re-log sheets

**Tracked nutrients (19 fields + water)**
Calories, Protein, Carbs, Fiber, Sugar, Total Fat, Saturated, Polyunsaturated, Monounsaturated, Trans, Cholesterol, Sodium, Potassium, Vitamin A, Vitamin C, Vitamin D, Calcium, Iron, Magnesium.

Critical design choice: optional fields use `Double?`. Empty form fields stay nil. Nil ≠ 0 anywhere — the breakdown displays "–" for unknown values rather than misleading zeros. This matters for sums (a vitamin total only counts entries that have that vitamin set) and will matter even more for averages over time periods.

**Tech stack**
- iOS 18+ (deploys to iOS 26.4 on Mike's iPhone 17 Pro Max)
- Xcode 26.4
- SwiftUI + SwiftData
- VisionKit `DataScannerViewController` for barcode scanning
- Open Food Facts API (free, no key) for product lookup
- Anthropic Messages API (claude-opus-4-7) for photo nutrition estimation
- Keychain for API key storage
- Git, committed phase by phase

**Project structure**
```
FoodJournal/
├── FoodJournalApp.swift              entry point, SwiftData container
├── Assets.xcassets
├── Models/
│   └── Models.swift                  FoodEntry, UserGoals, CachedFood, WaterEntry
├── Services/
│   ├── OpenFoodFactsService.swift    barcode → product lookup (full nutrition)
│   ├── ClaudeVisionService.swift     photo → nutrition estimate (full set)
│   └── KeychainStore.swift           API key storage
└── Views/
    ├── RootView.swift                tab bar
    ├── TodayView.swift               summary, macros, water, meal-grouped entries
    ├── AddFoodView.swift             recents (with timestamps + swipe-delete) + 3 input cards
    ├── BarcodeScannerSheet.swift
    ├── PhotoLogSheet.swift
    ├── NutritionBreakdownSheet.swift full breakdown of all 19 nutrients
    └── AuxViews.swift                ConfirmFoodView, ManualEntrySheet, SettingsView,
                                       RelogSheet, EditEntrySheet, dismissKeyboard,
                                       SelectAllOnFocus modifier
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R. First-time setup is documented in earlier conversation history (camera permission, developer mode on phone, trust certificate).

To use photo logging, paste an Anthropic API key in Settings (`sk-ant-...`). Get one at console.anthropic.com — needs at least a few dollars of credit. Photo logging costs <$0.01 per estimate.

When the SwiftData schema changes (which means anytime fields are added to FoodEntry or UserGoals), delete the app from your phone first (long-press icon → Remove App → Delete App), then run from Xcode. Migration from the previous schema isn't set up — fresh install is the simplest path.

## Known issues / quirks

- **Recents dedup is by name+brand** — if "apple" got logged once at 95 Calories and once at 80 Calories, only the most recent shows. Probably fine in practice. Removing from Recents deletes all matching history (intentional — otherwise the older copy would just resurrect).
- **Open Food Facts unit conversions** — sodium/calcium/iron/magnesium/potassium are converted from grams to mg, vitamins A/D from g to µg, vitamin C from g to mg. These conversions are right for ~95% of products. If a product reads dramatically wrong, it might be storing data in an unusual unit and we'd need a one-off fix.
- **No error UI for network failures on barcode scan** — Open Food Facts timeouts surface as "not found" which is misleading.
- **Goals beyond the 5 visible in Settings** are stored with sensible defaults (40g fiber, 50g sugar, 2300mg sodium, etc.) but not yet editable from the UI. They power the Full breakdown progress bars.
- **No haptic feedback on logging actions yet** — would feel nicer.
