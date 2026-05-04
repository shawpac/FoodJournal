# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.4. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Recently shipped

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

### Search by name + persistent food library
Combines two of Mike's asks: a USDA-backed search for fresh foods (so you can log "apple" without barcode hunting) AND a personal library of every unique food you've previously logged. One unified search that hits local first, USDA second.

Implementation: when you log a food, also save a `LibraryFood` record (deduped by name+brand). The Add tab gets a "Search" option that searches the local library, falling back to USDA's free FoodData Central API for unknown items. Picking either fills the Confirm screen.

USDA has ~400k foods. Hardest part is dealing with their multiple food types ("branded" / "foundation" / "survey") and picking sensible defaults. ~2 hours for v1, polish after.

### Trends view (weekly / monthly / custom range averages)
A new "Trends" tab. Top of the screen has a range selector (Last 7 days / Last 30 days / Custom range). Body shows average daily values for all 19 nutrients + calories + water with the same progress-bar UI as the breakdown sheet.

Critical design choice for averages: only count days that had data for that nutrient. Display as "12 µg Vitamin D — based on 3 of 7 days" so it's clear when an average isn't comprehensive. This preserves the "nil ≠ 0" philosophy from the entry model.

Apple's `Charts` framework also makes line charts easy if you want to see trend over time, not just averages. Probably ~2 hours total.

### Export your data to CSV
"Settings → Export" with a custom-range date picker. Generates a CSV of all entries in range, opens iOS share sheet so you can email/save it. Each row is one logged entry with all 19 nutrient fields as columns. ~30 min.

---

## Tier 2 — Useful but not urgent

### Undo for water deletes and Recents removal
v1.4 added undo for food entries only. Same pattern could extend to:
- Water entries swipe-delete in WaterEntriesSheet
- Recents swipe-delete in AddFoodView
~30 min for both. Recents is arguably the more useful one — accidentally removing a frequently-eaten food is annoying.

### iCloud sync across devices
Convert SwiftData container to use CloudKit. Data syncs to other Apple devices automatically. Comes with edge cases (conflicts, offline, free Apple ID limits CloudKit usage). Worth doing only if you actually use a second device. ~1-2 hours including testing.

### Notification reminders
Optional reminder to log dinner at 8pm if you haven't logged anything in 4 hours. Apple's `UserNotifications` framework. Get this wrong and it's annoying — get it right and you actually use the app daily.

### Smart auto-fill defaults
If you eat the same breakfast every weekday, the app should know that. After 2 weeks of data, suggest "Log your usual?" Tier 3 ML eventually, but a basic version is just "what did the user log between 7-10am yesterday."

### Better photo logging
- Re-prompt Claude with "are you sure?" if confidence is low
- Multi-photo support — sometimes one angle isn't enough
- Cache history with thumbnails would be a separate feature (and explicitly off the roadmap — Mike doesn't want photos balooning the DB)

---

## Tier 3 — Polish & advanced

### UI polish across the board
- Custom app icon
- Animated number transitions (calorie ring smoothly counting up when you add an entry)
- Better empty states with illustrations
- Dark mode tuning
- Custom typography — currently very system-default

### Macros breakdown by meal
Now that meal grouping exists on Today, this is a smaller addition: show how each macro is distributed across breakfast/lunch/dinner. Helps with timing ("I keep eating 80% of my carbs at dinner").

### Weight tracking
Stretch goal — simple weight log tab. Pairs well with the trends view.

### Apple Health integration
Two-way sync with Apple Health — Health gets your calorie/macro/water totals, you get weight and exercise from Health. Lots of edge cases but unlocks the "real" iOS experience. ~2-3 hours.

### Recipe support
"I made stir-fry with chicken, rice, broccoli, soy sauce." Save the combination as a named recipe so you can log it as one item next time. Simplest model: a recipe is just a saved meal of multiple FoodEntry rows that get inserted together.

### Real OCR of nutrition labels
Photo of nutrition facts panel → parsed into a CachedFood entry. Claude can already do this with the existing photo flow, just needs a different prompt and UI route. Fills the Open Food Facts gap nicely.

### Public release
Paid Apple Developer account ($99/year), App Store Connect setup, screenshots, privacy policy, marketing site. A few-day project on its own. The code's structured well enough that this isn't a big lift technically — the work is all in the surrounding artifacts.

---

## What I'd do next if I were you

The app is genuinely usable end-to-end at v1.4. Real usage will tell you what's missing better than any roadmap entry can.

In rough order:
1. **Use the app for 3-5 real days** before adding any new features. After v1.4 the surface area is solid; what's left is value-add, not foundation.
2. **CSV export** — easy, adds peace of mind for data ownership
3. **Search by name + food library** — once this exists, the app feels complete. No other v1 trackers compare.
4. **Trends view** — this is when "I've been tracking for a week" becomes "I'm noticing patterns."
5. **Undo for water/Recents** — bundle with any other small-fix session

The big ones (search, trends) are full-session efforts each. The small items in Tier 2 stack well — knock 2-3 out together.
