# FoodJournal — Project Context

A personal iOS nutrition tracker (SwiftUI + SwiftData) for Mike Shaw's iPhone 17 Pro Max. Single-developer, no remote, no collaborators. Personal use only — not on App Store. Currently v1.8.6.

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
- **Free Apple Developer Team** — CANNOT enable iCloud/CloudKit (the capability doesn't appear in Xcode's picker). HealthKit DOES work on the free team — confirmed working in v1.8.2.
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

Schema-change versions so far: v1.8 (WaterEntry.pendingDeleteAt + new WeightEntry), v1.8.2 (healthSampleID on FoodEntry/WaterEntry/WeightEntry, importedFromHealth on WeightEntry). v1.8.1, v1.8.3, v1.8.4, v1.8.5, v1.8.6 were schema-clean.

## Hard rules

- **Nil ≠ 0 anywhere.** Optional nutrient fields are `Double?`. Empty form input stays nil. Breakdown shows "–" for unknown, never "0". CSV exports nil as empty cells. Trends shows "based on N of M days" when partial coverage. Never silently convert nil to 0.

- **Never create files in Xcode with slashes in the name.** macOS converts slashes to colons → broken filenames like `Services:MealTimeHelper.swift`. Use plain identifiers, let Xcode place them via the New File dialog. The project uses synchronized folder groups, so files dropped into `FoodJournal/Services/` or `FoodJournal/Views/` via filesystem are auto-discovered — no .pbxproj edit needed.

- **Edit existing files directly via filesystem.** Don't generate large paste-blocks for the user. AuxViews.swift is now ~70KB; surgical paste-edits drift and silently fail. Direct edits avoid this entire class of bugs.

- **Never push to a remote.** No GitHub, no GitLab. Local only.

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

## File map (where to look)

- `FoodJournalApp.swift` — entry point, SwiftData container with 7 model types, owns NotificationCoordinator + registers as UN delegate.
- `Models/Models.swift` — all `@Model` classes (FoodEntry, UserGoals, CachedFood, WaterEntry, CachedPhotoEstimate, LibraryFood, WeightEntry) + `LibraryFoodUpsert` helper + `FoodFormat` enum.
- `Services/`
  - `MealTimeHelper.swift` — meal-window config (UserDefaults-backed, configurable in Settings since v1.8); late-night warning logic.
  - `LibraryService.swift`, `USDAService.swift`, `OpenFoodFactsService.swift` — search + product lookup.
  - `ClaudeVisionService.swift` — photo → nutrition estimate; supports multi-image (v1.8.5).
  - `KeychainStore.swift` — parameterized key storage (anthropic + usda).
  - `NotificationService.swift` (v1.8.1) — daily meal reminder scheduling.
  - `NotificationCoordinator.swift` (v1.8.1) — `@Observable` UN delegate for foreground display + tap-to-deep-link.
  - `HealthService.swift` (v1.8.2) — contains both `HealthService` (low-level HK ops) and `HealthSync` (orchestration). Read the file's header comments for the correlation-type gotcha.
  - `UsualSuggestionService.swift` (v1.8.6) — heuristic for "your usual breakfast/lunch/dinner" suggestion banner.
- `Views/RootView.swift` — TabView root, hoisted `selectedDate`, watches `NotificationCoordinator.pendingMealOpen` for deep-link to MealDetailSheet.
- `Views/TodayView.swift` — date-navigable dashboard. Hosts WaterEntriesSheet (nested) + MealDetailSheet (nested). Smart-suggestion banner (v1.8.6) sits above the daily totals card. Meal cards show P/C/F line below calories (v1.8.4). EntryRow recognizes `source == "suggestion"` for sparkles icon.
- `Views/AddFoodView.swift` — date-aware add tab + past-day banner + MostUsedSheet (nested).
- `Views/TrendsView.swift` — range picker, per-section averages, Weight section (always visible since v1.8), Distribution by meal section (v1.8.4), nested WeightEntriesSheet for log/manage.
- `Views/SearchSheet.swift` — library + USDA search + library swipe-add (v1.7.3) with HealthSync wiring (v1.8.2).
- `Views/NutritionBreakdownSheet.swift` — full 19-nutrient breakdown by selectedDate.
- `Views/BarcodeScannerSheet.swift`, `Views/PhotoLogSheet.swift` — scanner + photo log. PhotoLogSheet was rewritten in v1.8.5 around `images: [UIImage]` for multi-photo.
- `Views/CSVExportSheet.swift` — exports food/water/weight CSVs (v1.8.2 added weight).
- `Views/NutrientGoalsSheet.swift` — editable goals for the 14 secondary nutrients.
- `Views/AuxViews.swift` — ConfirmFoodView, ManualEntrySheet, EditEntrySheet, SettingsView (now contains Meal time schedule, Reminders, Smart suggestions, Apple Health sections), AnthropicKeySheet, USDAKeySheet, RelogSheet (dormant), dismissKeyboard, SelectAllOnFocus modifier, Haptic helper. Large file (~70KB) — search by `struct` keyword to navigate.

## Manual Xcode steps locked in (don't repeat in new sessions)

- **HealthKit capability** is enabled (Signing & Capabilities → HealthKit). `FoodJournal.entitlements` contains `com.apple.developer.healthkit = true`.
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
