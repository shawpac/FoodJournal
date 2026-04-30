# FoodJournal

A personal iOS nutrition tracker. Native SwiftUI + SwiftData, runs entirely on-device except for two API calls (Open Food Facts for barcode lookups, Claude for photo estimation).

Built collaboratively over a single afternoon — Claude wrote the code, Mike ran it, we iterated on bugs and features in real time.

## Current state (v1.1)

**Working features**
- Today tab with calorie ring, macro pills (protein / carbs / fat), and water tracking
- Water tracking: progress to daily goal, quick-tap buttons (−8 / +8 / +12 / +16), custom-amount text field with Log button
- Add tab with four input methods:
  - **Recents** — top 10 unique foods you've logged before, one tap to re-log with adjusted servings
  - **Scan barcode** — Open Food Facts lookup, opens confirm screen where you set grams
  - **Photo estimate** — Claude vision API estimates nutrition from a photo, shows confidence
  - **Manual entry** — type name and macros directly
- Settings tab: daily goals (calories, protein, carbs, fat, water) + Anthropic API key (stored in Keychain)
- SwiftData persistence — entries survive app restarts
- Swipe to delete entries on Today tab

**Tech stack**
- iOS 18+ (project deploys to iOS 26.4 on Mike's iPhone 17 Pro Max)
- SwiftUI + SwiftData
- VisionKit `DataScannerViewController` for barcode scanning
- Open Food Facts API (free, no key) for product lookup
- Anthropic Messages API (claude-opus-4-7) for photo nutrition estimation
- Keychain for API key storage

**Project structure**
```
FoodJournal/
├── FoodJournalApp.swift         entry point, SwiftData container setup
├── Assets.xcassets
├── Models/
│   └── Models.swift             FoodEntry, UserGoals, CachedFood, WaterEntry
├── Services/
│   ├── OpenFoodFactsService.swift   barcode → product lookup
│   ├── ClaudeVisionService.swift    photo → nutrition estimate
│   └── KeychainStore.swift          API key storage
└── Views/
    ├── RootView.swift           tab bar
    ├── TodayView.swift          summary, macros, water, entries list
    ├── AddFoodView.swift        recents + 3 input cards
    ├── BarcodeScannerSheet.swift
    ├── PhotoLogSheet.swift
    └── AuxViews.swift           ConfirmFoodView, ManualEntrySheet, SettingsView, RelogSheet
```

## Running it

Plug iPhone in, open the project in Xcode, hit ⌘R. First-time setup is documented in the conversation history if needed (camera permission, developer mode on phone, trust certificate).

To use photo logging, paste an Anthropic API key in Settings (`sk-ant-...`). Get one at console.anthropic.com — needs at least a few dollars of credit. Photo logging costs <$0.01 per estimate.

## Known issues

- **Water `−8` button deletes the most recent entry instead of subtracting 8 oz.** Inconsistent with the custom-amount field which inserts a negative entry. Fix: change `logWater` to always insert (positive or negative); separately add a way to delete a specific water entry from a list view.
- **No way to edit an existing food entry** after it's logged. You can only delete and re-add.
- **Recents list is unique-by-name+brand**, so if you log "apple" once with 95 kcal and once with 80 kcal, only the most recent shows up. Probably fine in practice but worth noting.
- **Open Food Facts misses many US products.** Particularly fresh produce, store brands, and small regional brands. The "search by name" feature on the roadmap will help.
- **No error UI for network failures on barcode scan.** Open Food Facts timeouts surface as "not found" which is misleading.
