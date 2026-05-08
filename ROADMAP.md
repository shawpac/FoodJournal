# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.7.1. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Recently shipped

### v1.7.1 — Date-navigable Today tab + past-day logging

**The "I forgot to log yesterday" problem, solved.**

**Today tab is now date-navigable:**
- ✅ Chevron buttons (`‹` / `›`) in the toolbar step the view backward and forward by day. Forward chevron is disabled when on today.
- ✅ Tap the title (which shows "Today" / "Yesterday" / formatted date like "Mon, May 4") → opens a date-picker sheet with a graphical calendar.
- ✅ Future dates are visually disabled in the picker.
- ✅ "Today" button in the picker's nav bar for instant jump-back.
- ✅ All cards (daily totals, water, meal cards, Full breakdown) reflect the selected day's data.

**Past-day logging:**
- ✅ Water card's "Log" button creates a WaterEntry on the selected day. Custom-amount entry, set-total alert, and individual entry deletion in WaterEntriesSheet all respect the selected day. Entries on past days are timestamped at noon of that day; today entries use real-time.
- ✅ Meal cards' "+ Add to {meal}" buttons thread the selected date through Search / Barcode / Photo / Manual entry → entries land on the right day.
- ✅ WaterEntriesSheet titled appropriately ("Today's water" / "Yesterday's water" / formatted date).
- ✅ EditEntrySheet preserves an entry's `loggedAt` date — editing yesterday's entry doesn't move it to today.

**Architecture:**
- ✅ Threaded `defaultDate: Date?` parameter alongside the existing `defaultMeal: String?` through ConfirmFoodView, ManualEntrySheet, BarcodeScannerSheet, SearchSheet, PhotoLogSheet. All five default to `nil` for backward compatibility — `nil` falls through to `.now`, so the Add tab keeps logging to today as before.
- ✅ Used mutation pattern (`entry.loggedAt = defaultDate`) for FoodEntry saves to avoid coupling to init parameter order.
- ✅ MealDetailSheet now accepts `selectedDate: Date` and threads it to all four input sheets.
- ✅ Pure UI/wiring change — no schema modification, no app reinstall required.

**Intentional scope decisions:**
- The Add tab (global) always logs to today, regardless of Today's selectedDate. The Add tab is "log something now"; past-day logging routes through Today's meal cards.
- EditEntrySheet does not get a date picker. Moving an entry to a different day is rare enough to handle via delete + re-log.
- Past-day entries are timestamped at noon of that day. Hour-of-day doesn't matter for display (meal grouping is by `mealType` field) so this is a clean default.

### v1.7 — Trends, Most Used undo, totals-mode entry, configurable late-night alert

**Trends tab:**
- ✅ New 4th tab (Today → Add → Trends → Settings) with line-chart icon.
- ✅ Range selector: 7 days / 30 days / Custom (with date pickers, future-date prevention).
- ✅ Daily averages for all 19 nutrients + water + calories, organized into the same five sections as the breakdown sheet.
- ✅ Progress bars for the 5 main goals; numeric averages only for the rest.
- ✅ "Based on N of M days" caption when coverage is partial — preserves nil ≠ 0 honesty.
- ✅ Empty state with chart icon when no data is in range.
- ✅ Pure read-only aggregation, no schema change.

**Most Used undo:**
- ✅ Swipe-left "Remove" greys the row to 35% opacity and shows a 5-second undo toast.
- ✅ Greyed rows are non-tappable during the window.
- ✅ Dismissing the sheet commits any pending deletes immediately.
- ✅ No schema change: undo lives entirely in transient view state.

**Manual entry per-serving / totals mode:**
- ✅ Segmented picker at the top of the Serving section: "Per serving" / "Total amount" (default Per serving).
- ✅ In totals mode, "Servings" label flips to "Amount," macros section header flips to "Macros (totals)."
- ✅ On save, totals-mode values are divided by the amount to derive per-serving — storage layer unchanged.
- ✅ Resolves the 100×380=38,000 cal wart for new entries.
- ✅ EditEntrySheet intentionally does NOT get the toggle.

**Late-night warning customization:**
- ✅ "Late-night snack alert" section in Settings: toggle + Start/End hour pickers.
- ✅ Defaults match v1.6 hardcoded behavior (8pm–6am, enabled).
- ✅ Window math handles wrap-around and same-day windows.
- ✅ Persisted via `@AppStorage` — no schema change.

### v1.6 — Today redesign + meal context everywhere

**Today tab redesign:**
- ✅ Daily totals card with four equally-sized horizontal stat tiles.
- ✅ Always-visible meal cards with ghosted empty state.
- ✅ Tap any meal card → MealDetailSheet with per-meal totals, swipe-delete with undo, and a four-button "+ Add to {meal}" section.
- ✅ Picking a food from a meal card pre-tags the meal context.

**Most Used replaces Recents on Add tab:**
- ✅ Single "Most Used" card with purple star icon → opens MostUsedSheet listing top 10 library foods.
- ✅ Sorted by hybrid score (`useCount + recency * 5`) — same algorithm as Search.

**Pre-tagged meal context plumbing:**
- ✅ `defaultMeal: String?` parameter threaded through ConfirmFoodView, ManualEntrySheet, RelogSheet, SearchSheet, BarcodeScannerSheet, PhotoLogSheet.

**Time-derived meal defaults + late-night confirmation:**
- ✅ `MealTimeHelper` enum classifies the current hour into breakfast/lunch/dinner/snack.
- ✅ Saving a snack between 8pm–6am triggers an alert (configurable in v1.7).

### v1.5 — search + library + cleaner Settings + identity

- ✅ `LibraryFood` SwiftData model + passive upsert from every save path.
- ✅ Hybrid storage (per-100g vs per-serving via `isPer100g` flag).
- ✅ `LibraryService.search()` and `USDAService.search()` — local + USDA debounced.
- ✅ Unified `SearchSheet`.
- ✅ CSV export with date range picker, dual-CSV via share sheet.
- ✅ Reset food library destructive button.
- ✅ API keys section condensed to compact rows + focused edit sheets.
- ✅ Custom devil-fruit-themed app icon (Gemini-generated).

### v1.4 — quick wins + cost-down on photo logging
- ✅ Switched to Claude Sonnet 4.6 (~5x cheaper per call).
- ✅ Confirmation step before sending photo (Analyze button).
- ✅ Image-hash caching.
- ✅ Camera-based photo capture replaces photo library picker.
- ✅ Number rounding, friendlier empty states, haptic feedback, editable goals for all 14 secondary nutrients, 5-second undo on swipe-delete.

### v1.3
- ✅ "Calories" instead of "kcal", click-to-edit any logged entry, serving unit dropdown with Custom… option, better Recents (relative timestamps + swipe-left), meal grouping on Today, select-all-on-focus on numeric fields.

---

## Tier 1 — The v1.8 schema-change bundle

These three items all require a SwiftData schema change. Bundling them into a single session means **one app reinstall covers all three**, instead of a separate reinstall for each. Always export CSV first via Settings → Data → Export.

### Water entry undo
v1.4 added undo for food entries; v1.7 added it for Most Used. The remaining gap is water — swipe-deleting a water entry in WaterEntriesSheet still commits immediately.

⚠️ **Schema change required:** `WaterEntry` doesn't have `pendingDeleteAt` yet. Adding it follows the same pattern that `FoodEntry` already uses.

~15 min of work once the schema reset is in motion.

### Weight tracking
Simple weight log tab (or a section in an existing tab). Pairs naturally with the Trends view — averaging weight over time is exactly the kind of thing Trends is good at.

⚠️ **Schema change required:** new `WeightEntry` `@Model` with `loggedAt: Date`, `weightLbs: Double` (or `weightKg`, depending on user preference — could just expose both display modes via Settings later).

Adding a 5th tab might crowd the bar; an alternative is integrating weight into the Trends tab as a top-level section. Decide during the session.

~30–45 min.

### Custom meal-time schedules
The current `MealTimeHelper` hardcodes a 9-to-5-ish schedule. Make the windows user-editable in Settings — useful for shift workers, intermittent fasters, or anyone whose schedule doesn't match the default.

⚠️ **Schema change required** if persisted as a `@Model` class. Alternative: persist via @AppStorage (similar to the v1.7 late-night config) — six integers for the boundary hours. The @AppStorage route would actually avoid the schema change. Decide during the session.

~30 min.

**Total for the bundle:** ~1–2 hours including reinstall and verification.

---

## Tier 2 — Useful but not urgent (no schema change)

### Past-day entry timestamps
v1.7.1 timestamps past-day entries at noon. WaterEntriesSheet shows them all as "12:00 PM" which is technically misleading. Could add a time picker in WaterEntriesSheet's add flow, or a mini time picker on the meal-card "+ Add" buttons when on a past day. Low priority since totals/display are unaffected.

### Date editing in EditEntrySheet
v1.7.1 doesn't let you change an entry's `loggedAt` after the fact. To move an entry to a different day, you delete and re-log. Adding a `loggedAt` picker to EditEntrySheet would be straightforward — `DatePicker(in: ...Date.now)` next to the meal picker. ~10 min.

### Smart auto-fill defaults
If you eat the same breakfast every weekday, the app should know that. After 2 weeks of data, suggest "Log your usual?" Now that v1.7 has Trends, v1.6 has Most Used + library, and v1.7.1 makes past-day data easily browsable, the foundation is solid — basic version is "what did the user log between 7-10am yesterday."

Could surface as a banner at the top of Today during meal windows ("Your usual breakfast?") or as a smart row at the top of Most Used.

### Notification reminders
Optional reminder to log dinner at 8pm if you haven't logged anything in 4 hours. Apple's `UserNotifications` framework. Get this wrong and it's annoying — get it right and you actually use the app daily.

The v1.7 late-night warning is essentially a notification-equivalent inside the app. A real local notification would extend the same nudge to outside the app.

### Apple Health integration
Two-way sync with Apple Health — Health gets your calorie/macro/water totals, you get weight and exercise from Health. Lots of edge cases (units, deduplication, write conflicts) but unlocks the "real" iOS experience. ~2–3 hours, deserves its own focused session.

If weight tracking lands in v1.8 first, this becomes a natural follow-up — Health writes weight, app reads it, no manual entry.

### Better photo logging
- Re-prompt Claude with "are you sure?" if confidence is low.
- Multi-photo support — sometimes one angle isn't enough.
- (Cache history with thumbnails is explicitly off the roadmap — Mike doesn't want photos ballooning the DB.)

### Macros breakdown by meal
Now that meal cards exist on Today and Trends shows daily averages, this is the natural next slice: show how each macro is distributed across breakfast/lunch/dinner. Helps with timing ("I keep eating 80% of my carbs at dinner"). Could live inline on each meal card as a tiny sparkline or pill row, or as a new section at the bottom of Trends.

### iCloud / CloudKit sync across devices
Convert SwiftData container to use CloudKit. Data syncs to other Apple devices automatically.

⚠️ **Requires the paid Apple Developer Program ($99/year).** Free Apple ID accounts cannot enable iCloud capability. Confirmed — the iCloud capability simply doesn't appear in the Xcode capability picker on a free team.

⚠️ **Major schema audit:** every property on every `@Model` class must become optional or have a default value. Final reset is required, after which proper lightweight migrations replace the delete-and-reinstall workflow.

Worth doing only if Mike (a) actually starts using a second Apple device, or (b) decides to pursue App Store release (which the $99 also unlocks). Until then, deferred.

---

## Tier 3 — Polish & advanced

### UI polish across the board
- Animated number transitions (stat tiles smoothly counting up when you add an entry).
- Better empty states with illustrations.
- Dark mode tuning.
- Custom typography — currently very system-default.
- Tinted variant of the app icon for iOS appearance modes (currently same image used for all).
- Clean up the wonky indentation in BarcodeScannerSheet's ConfirmFoodView call (cosmetic only).

### Recipe support
"I made stir-fry with chicken, rice, broccoli, soy sauce." Save the combination as a named recipe so you can log it as one item next time. Simplest model: a recipe is just a saved meal of multiple FoodEntry rows that get inserted together.

⚠️ Schema change required (new `@Model` class). Could be bundled into a v1.9+ schema session if other items pile up.

### Real OCR of nutrition labels
Photo of nutrition facts panel → parsed into a CachedFood entry. Claude can already do this with the existing photo flow, just needs a different prompt and UI route. Fills the Open Food Facts gap nicely. No schema change.

### EditEntrySheet totals mode (deferred from v1.7)
The Manual entry totals toggle is per-serving-only on the edit side. Adding totals editing is doable but tricky — the existing entry is already in per-serving form, and re-deriving on every keystroke gets confusing. Defer until/unless someone actually asks.

### Public release
Paid Apple Developer account ($99/year), App Store Connect setup, screenshots, privacy policy, marketing site. Also requires: replacing the AI-generated devil-fruit icon with original art. A few-day project on its own. The code's structured well enough that this isn't a big lift technically — the work is all in the surrounding artifacts.

---

## What I'd do next if I were you

The app is in a really good place at v1.7.1. Date navigation closes the last big daily-friction gap — you can now fix forgotten logs from any past day, view trends with confidence in the data, and the totals-mode toggle removes the manual-entry footgun. Combined with v1.6's meal-card dashboard and Most Used, the daily-driver loop is tight.

In rough order:

1. **Use the app for 7–14 real days** before adding more features. v1.7.1 is the first version where Trends has meaningful data AND you can fix retroactively. You'll need real usage to see what patterns emerge and what new friction surfaces.

2. **v1.8 schema-change bundle** — water undo, weight tracking, custom meal schedules. One reinstall covers all three. Probably 1–2 hours.

3. **EditEntrySheet date picker + past-day timestamp picker** — small Tier 2 items that close the editing-flexibility loop. ~30 min combined.

4. **Smart auto-fill or notifications** — pick whichever feels more useful after a couple weeks of use. Auto-fill if logging speed is the friction; notifications if remembering to log is the friction.

5. **Apple Health integration** — once weight tracking is in, this becomes the natural unlock. Pairs especially well with iPhone's existing fitness data.

6. **CloudKit + App Store** — gated on the $99 decision. Still deferred.

The remaining big items (CloudKit, recipes, public release) are all gated on either money, time, or both. Defer until pulled.
