# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.2. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Next up — small fixes & high-leverage cleanups

These are the daily-friction items. Small, contained, big payoff.

### "Calories" instead of "kcal"
One-word find/replace across the app. Trivial.

### Click into and edit any logged entry
Right now if you log a chicken sandwich at 1 serving and realize it was 1.5, you have to delete and re-add. Tap any entry on Today → opens an edit sheet with all the fields editable. The `RelogSheet` UI we already built is most of the work; this is "open it on an existing entry instead of creating a new one." ~30 min.

### Serving unit dropdown in manual entry
Currently a free text field. Replace with a picker containing common units (grams, milliliters, ounces, serving, piece, cup, tbsp, tsp, slice) plus a "Custom…" option that opens a text field for unusual cases like "1 burrito." ~20 min.

### Fix the water −8 button (legacy, may already be done)
Verify this is fixed in current build. Earlier the `-8` button deleted the most recent water entry instead of subtracting 8 oz. The "set total directly" feature replaced this, but check that the legacy quick-tap buttons (if any remain) behave correctly.

### Better Recents
Two small improvements:
1. Show "Last logged: yesterday at 8am" so you can recognize what you're picking
2. Long-press to delete from recents (in case something one-time gets stuck there)

### Polish that emerges from real use
You'll spot these as you use the app. Examples:
- Numbers should round better (3.0 → 3, not 3.0)
- Barcode scanner needs a clear "tap to scan again" if it misreads
- Haptic feedback on logging actions

---

## Tier 1 — Will improve daily use most

### Meal grouping on Today (Breakfast / Lunch / Dinner / Snack)
Today tab currently shows one flat list of entries. Group by meal type with running subtotals per meal. Helps you see what's eating your calorie budget. The `mealType` field already exists on every entry — pure UI work. ~30 min.

### Edit logged-entry's full nutrient set
Extension of "click into and edit any logged entry" above — if the entry has all 19 nutrient fields filled (e.g., from a photo estimate), the edit sheet should let you adjust all of them, not just servings.

### Search by name + persistent food library
Combines two of Mike's asks: a USDA-backed search for fresh foods (so you can log "apple" without barcode hunting) AND a personal library of every unique food you've previously logged. One unified search that hits local first, USDA second.

Implementation: when you log a food, also save a `LibraryFood` record (deduped by name+brand). The Add tab gets a "Search" option that searches the local library, falling back to USDA's free FoodData Central API for unknown items. Picking either fills the Confirm screen.

USDA has ~400k foods. Hardest part is dealing with their multiple food types ("branded" / "foundation" / "survey") and picking sensible defaults. ~2 hours for v1, polish after.

### Trends view (weekly / monthly / custom range averages)
A new "Trends" tab. Top of the screen has a range selector (Last 7 days / Last 30 days / Custom range). Body shows average daily values for all 19 nutrients + calories + water with the same progress-bar UI as the breakdown sheet.

Critical design choice for averages: only count days that had data for that nutrient. Display as "12 µg Vitamin D — based on 3 of 7 days" so it's clear when an average isn't comprehensive. This preserves the "nil ≠ 0" philosophy from the entry model.

Apple's `Charts` framework also makes line charts easy if you want to see trend over time, not just averages. Probably ~2 hours total.

### Entry deletion that actually undoes
Right now swipe-to-delete is permanent. iOS users expect a brief "undo" snackbar at the bottom. Saves a real "oh shit" moment when you misclick. ~20 min.

---

## Tier 2 — Useful but not urgent

### Export your data to CSV
"Settings → Export" with a custom-range date picker. Generates a CSV of all entries in range, opens iOS share sheet so you can email/save it. Each row is one logged entry with all 19 nutrient fields as columns. ~30 min.

### iCloud sync across devices
Convert SwiftData container to use CloudKit. Data syncs to other Apple devices automatically. Comes with edge cases (conflicts, offline, free Apple ID limits CloudKit usage). Worth doing only if you actually use a second device. ~1-2 hours including testing.

### Better photo logging
- Take photo directly in-app instead of only library
- Show photo as a thumbnail on the logged entry
- Re-prompt Claude with "are you sure?" if confidence is low
- Cache photo locally so you can review history
- Multi-photo support — sometimes one angle isn't enough

### Notification reminders
Optional reminder to log dinner at 8pm if you haven't logged anything in 4 hours. Apple's `UserNotifications` framework. Get this wrong and it's annoying — get it right and you actually use the app daily.

### Smart auto-fill defaults
If you eat the same breakfast every weekday, the app should know that. After 2 weeks of data, suggest "Log your usual?" Tier 3 ML eventually, but a basic version is just "what did the user log between 7-10am yesterday."

### Goals UI for all 19 nutrients
Currently Settings only exposes calories/protein/carbs/fat/water. The other 14 nutrient goals are stored with sensible defaults but not editable. Add a "More goals" section.

---

## Tier 3 — Polish & advanced

### UI polish across the board
- Custom app icon
- Animated number transitions (calorie ring smoothly counting up when you add an entry)
- Better empty states with illustrations
- Dark mode tuning
- Custom typography — currently very system-default

### Macros breakdown by meal
Show how each macro is distributed across breakfast/lunch/dinner. Helps with timing ("I keep eating 80% of my carbs at dinner").

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

In rough order:
1. **"Calories" rename + edit-logged-entry + meal grouping** — these three together transform daily feel
2. **Serving unit picker** — small change, removes typos
3. **Search by name + food library** — once you have it, no other v1 trackers compare
4. **Trends view (averages)** — this is when "I've been tracking for a week" becomes "I'm noticing patterns"
5. **CSV export** — easy, adds peace of mind
6. **Use the app for a real week between 1 and 4** — what feels missing in real use is what to build next, not what's on this list

The smaller items in "Next up" stack well — knock 3-4 out in one session. The bigger items (search, trends) are full-session efforts on their own.
