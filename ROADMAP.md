# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.8.6. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Recently shipped

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

The app is in a really good place at v1.8.6. Tier 1 + Tier 2 (minus iCloud) are fully shipped — that's seven version bumps in the last session. The daily-driver loop is now genuinely tight:
- Logging is one tap (Most Used / suggestion banner / SearchSheet swipe-add) or a guided flow.
- Past-day support works end-to-end with proper time fidelity.
- Editing is fully flexible — every field, date, time, plus delete-with-undo.
- Trends shows longitudinal weight, macros, distribution by meal, and per-nutrient averages.
- Apple Health mirrors everything; reminders nudge from outside the app.

In rough order for next time:

1. **Use the app for 7–14 real days** before adding more features. v1.8.6 is the first version where the smart-suggestion banner can actually surface (needs 14 days of patterned data). Real usage will tell whether the heuristic is right.

2. **Recipe support** — highest-value Tier 3 item. Single new `@Model` + a new sheet to compose and a Most-Used-style integration point. Schema change so bundle anything else that's pending.

3. **OCR of nutrition labels** — quick win once recipes are in. Adds value for unbranded products not in Open Food Facts.

4. **UI polish** — low-priority, but a tinted app icon variant and a few small empty-state illustrations would round things out.

5. **CloudKit + App Store** — gated on the $99 decision. Still deferred.
