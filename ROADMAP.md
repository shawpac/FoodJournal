# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.5. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Recently shipped

### v1.5 — search + library + cleaner Settings + identity

**Search by name + persistent food library:**
- ✅ New `LibraryFood` SwiftData model — one record per unique food name+brand combo
- ✅ Passive upsert from every save path (manual, barcode, photo, search, re-log, edit) — library grows on its own
- ✅ Hybrid storage: per-100g for gram-based logs, per-serving for cup/tbsp/"burrito" logs (`isPer100g` flag distinguishes)
- ✅ `LibraryService.search()` — local substring match scored by useCount + recency
- ✅ `USDAService.search()` — async FoodData Central queries with parens force-encoded for nginx compatibility
- ✅ New `SearchSheet` view: instant library results above debounced USDA results, branded-foods toggle, single tap → ConfirmFoodView
- ✅ "Search foods" card on the Add tab (new top option, green tint)
- ✅ USDA key stored in Keychain alongside the existing Anthropic key (parameterized via `KeychainStore.Key` enum)

**CSV export:**
- ✅ Settings → Data → Export data with date range picker (default last 30 days)
- ✅ Outputs two CSVs (food + water) bundled in the iOS share sheet
- ✅ Nil nutrients render as empty cells (preserves nil ≠ 0 invariant)
- ✅ Soft-deleted entries pending undo are excluded
- ✅ Filenames include the date range: `FoodJournal-food-2026-04-03-to-2026-05-03.csv`

**Confirm screen ergonomics:**
- ✅ Top-right Save button (matches Manual Entry / Edit Entry)
- ✅ Select-all-on-focus on the grams field
- ✅ Done button on keyboard accessory bar

**Settings cleanup:**
- ✅ "Save goals" button moved to top-right nav bar (matches Manual Entry / Edit Entry)
- ✅ API keys section condensed to two compact rows showing "Set" (green) or "Not set" (gray) status
- ✅ Each key gets a focused edit sheet with SecureField, linkified footer, Save and Clear-key buttons, transient confirmation message, auto-dismiss on save
- ✅ Linkified footers tap to open Safari (console.anthropic.com / api.data.gov/signup)
- ✅ "Reset food library" destructive button with confirmation alert showing record count

**Identity:**
- ✅ Custom devil-fruit-themed app icon (Gemini-generated, dropped into Assets.xcassets)

### v1.4 — quick wins + cost-down on photo logging

**Photo logging cost optimization:**
- ✅ Switched to Claude Sonnet 4.6 (~5x cheaper per call than Opus, no accuracy loss for food photos)
- ✅ Confirmation step before sending photo (Analyze button — prevents accidental API charges)
- ✅ Image-hash caching (re-logging the same photo returns instantly with no API call; hashes pixel data, not JPEG bytes)
- ✅ Capped `max_tokens` at 1024 (guards against runaway responses)
- ✅ Camera-based photo capture replaces photo library picker (snap the meal in front of you)

**Quick-win polish pass:**
- ✅ Number rounding: "3" not "3.0", "<0.1" for tiny values, "2.5" for fractional
- ✅ Friendlier empty states (Today tab + water entries sheet)
- ✅ Haptic feedback on logging, saving, and destructive actions
- ✅ Editable goals for all 14 secondary nutrients (fiber, sugar, fats detail, electrolytes, vitamins, minerals)
- ✅ Undo on swipe-delete with 5-second toast (food entries only)

### v1.3

- ✅ "Calories" instead of "kcal"
- ✅ Click into and edit any logged entry — full 19-field edit sheet
- ✅ Serving unit dropdown with Custom… option
- ✅ Better Recents — relative timestamps + swipe-left to remove
- ✅ Meal grouping on Today (Breakfast / Lunch / Dinner / Snacks with subtotals)
- ✅ Select-all-on-focus on numeric fields

---

## Tier 1 — Will improve daily use most

### Trends view (weekly / monthly / custom range averages)
A new "Trends" tab. Top of the screen has a range selector (Last 7 days / Last 30 days / Custom range). Body shows average daily values for all 19 nutrients + calories + water with the same progress-bar UI as the breakdown sheet.

Critical design choice for averages: only count days that had data for that nutrient. Display as "12 µg Vitamin D — based on 3 of 7 days" so it's clear when an average isn't comprehensive. This preserves the "nil ≠ 0" philosophy from the entry model.

Apple's `Charts` framework also makes line charts easy if you want to see trend over time, not just averages. Probably ~2 hours total.

**No schema change required** — pure read-only aggregation over existing data. Won't require app reinstall.

---

## Tier 2 — Useful but not urgent

### Undo for water deletes and Recents removal
v1.4 added undo for food entries only. Same pattern could extend to:
- Water entries swipe-delete in WaterEntriesSheet
- Recents swipe-delete in AddFoodView

⚠️ **Schema change required for water:** `WaterEntry` doesn't have `pendingDeleteAt` yet. Adding it = app reinstall (export CSV first). Recents undo is structurally simpler — it's still a `FoodEntry` deletion, no new field needed.

~30 min for both. Recents is arguably the more useful one — accidentally removing a frequently-eaten food is annoying.

### Notification reminders
Optional reminder to log dinner at 8pm if you haven't logged anything in 4 hours. Apple's `UserNotifications` framework. Get this wrong and it's annoying — get it right and you actually use the app daily.

No schema change.

### Smart auto-fill defaults
If you eat the same breakfast every weekday, the app should know that. After 2 weeks of data, suggest "Log your usual?" Tier 3 ML eventually, but a basic version is just "what did the user log between 7-10am yesterday."

The library that v1.5 built is a great foundation for this. No schema change needed.

### Better photo logging
- Re-prompt Claude with "are you sure?" if confidence is low
- Multi-photo support — sometimes one angle isn't enough
- Cache history with thumbnails would be a separate feature (and explicitly off the roadmap — Mike doesn't want photos ballooning the DB)

### iCloud / CloudKit sync across devices
Convert SwiftData container to use CloudKit. Data syncs to other Apple devices automatically.

⚠️ **Requires the paid Apple Developer Program ($99/year).** Free Apple ID accounts cannot enable iCloud capability. Confirmed during the v1.5 session — the iCloud capability simply doesn't appear in the Xcode capability picker on a free team.

⚠️ **Major schema audit:** every property on every `@Model` class must become optional or have a default value. Final reset is required, after which proper lightweight migrations replace the delete-and-reinstall workflow.

Worth doing only if Mike (a) actually starts using a second Apple device, or (b) decides to pursue App Store release (which the $99 also unlocks). Until then, deferred.

---

## Tier 3 — Polish & advanced

### UI polish across the board
- Animated number transitions (calorie ring smoothly counting up when you add an entry)
- Better empty states with illustrations
- Dark mode tuning
- Custom typography — currently very system-default
- Tinted variant of the app icon for iOS appearance modes (currently same image used for all)

### Macros breakdown by meal
Now that meal grouping exists on Today, this is a smaller addition: show how each macro is distributed across breakfast/lunch/dinner. Helps with timing ("I keep eating 80% of my carbs at dinner").

### Weight tracking
Stretch goal — simple weight log tab. Pairs well with the trends view. Schema change.

### Apple Health integration
Two-way sync with Apple Health — Health gets your calorie/macro/water totals, you get weight and exercise from Health. Lots of edge cases but unlocks the "real" iOS experience. ~2-3 hours. No schema change.

### Recipe support
"I made stir-fry with chicken, rice, broccoli, soy sauce." Save the combination as a named recipe so you can log it as one item next time. Simplest model: a recipe is just a saved meal of multiple FoodEntry rows that get inserted together.

⚠️ Schema change required (new `@Model` class).

### Real OCR of nutrition labels
Photo of nutrition facts panel → parsed into a CachedFood entry. Claude can already do this with the existing photo flow, just needs a different prompt and UI route. Fills the Open Food Facts gap nicely. No schema change.

### Manual-entry "totals mode" affordance
Address the v1.5-known-issue where typing 100 servings × 380 cal yields 38,000 cal. Either a smart inference ("if unit is 'g' and servings > 10, treat as totals") or a UI toggle ("entering totals" vs "entering per-serving"). Defer until search-driven logging is the dominant flow and we see whether this still happens.

### Public release
Paid Apple Developer account ($99/year), App Store Connect setup, screenshots, privacy policy, marketing site. Also requires: replacing the AI-generated devil-fruit icon with original art. A few-day project on its own. The code's structured well enough that this isn't a big lift technically — the work is all in the surrounding artifacts.

---

## What I'd do next if I were you

The app is genuinely usable end-to-end at v1.5. Search makes the daily-driver loop substantially better — most foods will be one tap away after a week or two of logging. Real usage will tell you what's missing better than any roadmap entry can.

In rough order:
1. **Use the app for 5-7 real days** before adding any new features. After v1.5 the surface area is solid; what's left is polish and incremental wins. Real usage will surface what trends should actually emphasize.
2. **Trends view** — this is when "I've been tracking for a week" becomes "I'm noticing patterns." Most natural next big feature, no schema change.
3. **Tier 2 cleanup bundle** — Recents undo + notification reminders + maybe smart auto-fill. Stack 2-3 of these in one session.
4. **CloudKit + App Store** — if/when you decide to pay the $99, both unlock together. This is also when the icon needs replacement with original art.

The remaining big items (CloudKit, recipes, App Store) are all gated on either money, time, or both. Defer until pulled.
