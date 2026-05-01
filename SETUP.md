# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for two API calls (Open Food Facts for barcode lookups, Claude for photo estimation).

Built collaboratively across two sessions — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.2)

**Working features**

*Today tab*
- Calorie ring, three macro pills (protein / carbs / fat), water tracking card
- Tap calorie ring → "Full breakdown" sheet showing all 19 nutrients with progress bars in five sections
- Water: tap the count to set a new total directly (logs the diff), long-press to see today's individual entries with delete
- Custom-amount water field with negative numbers supported
- Swipe-to-delete on logged food entries

*Add tab*
- **Recents** — top 10 unique foods, one tap opens re-log sheet
- **Scan barcode** — Open Food Facts lookup pulls full nutrition (macros + fiber, sugar, fats detail, cholesterol, sodium, potassium, vitamins A/C/D, calcium, iron, magnesium where available)
- **Photo estimate** — Claude vision API estimates everything it reasonably can; honestly returns nil for fields it can't see
- **Manual entry** — full form with sections for macros, carbs detail, fats detail, electrolytes, vitamins & minerals. Optional fields stay blank instead of defaulting to 0

*Settings*
- Daily goals for calories, protein, carbs, fat, water (additional goals stored but not yet editable from UI)
- Anthropic API key stored in Keychain

*Throughout*
- Save/Log buttons dismiss the keyboard
- Done button on numeric keypad in long forms

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
    ├── TodayView.swift               summary, macros, water, entries list
    ├── AddFoodView.swift             recents + 3 input cards
    ├── BarcodeScannerSheet.swift
    ├── PhotoLogSheet.swift
    ├── NutritionBreakdownSheet.swift full breakdown of all 19 nutrients
    └── AuxViews.swift                ConfirmFoodView, ManualEntrySheet, SettingsView, RelogSheet
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R. First-time setup is documented in earlier conversation history (camera permission, developer mode on phone, trust certificate).

To use photo logging, paste an Anthropic API key in Settings (`sk-ant-...`). Get one at console.anthropic.com — needs at least a few dollars of credit. Photo logging costs <$0.01 per estimate.

When the SwiftData schema changes (which means anytime fields are added to FoodEntry or UserGoals), delete the app from your phone first (long-press icon → Remove App → Delete App), then run from Xcode. Migration from the previous schema isn't set up — fresh install is the simplest path.

## Known issues / quirks

- **No way to edit a logged food entry** — only delete and re-add. Highest-priority fix on the roadmap.
- **Recents dedup is by name+brand** — if "apple" got logged once at 95 kcal and once at 80 kcal, only the most recent shows. Probably fine in practice.
- **Open Food Facts unit conversions** — sodium/calcium/iron/magnesium/potassium are converted from grams to mg, vitamins A/D from g to µg, vitamin C from g to mg. These conversions are right for ~95% of products. If a product reads dramatically wrong, it might be storing data in an unusual unit and we'd need a one-off fix.
- **No error UI for network failures on barcode scan** — Open Food Facts timeouts surface as "not found" which is misleading.
- **Goals beyond the 5 visible in Settings** are stored with sensible defaults (40g fiber, 50g sugar, 2300mg sodium, etc.) but not yet editable from the UI. They power the Full breakdown progress bars.
