# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.3. Higher items have higher value-per-hour-of-work; lower items are nice but optional. Priorities reflect real friction Mike hits using the app, not just feature wishlist.

---

## Recently shipped (v1.3)

For reference, since this got asked. ✅ items have been completed:

- ✅ "Calories" instead of "kcal" — shows as "Calories" in headers, "cal" in compact rows
- ✅ Click into and edit any logged entry — full 19-field edit sheet, all nutrients editable
- ✅ Serving unit dropdown (grams/ml/oz on top, plus serving/cup/tbsp/tsp, plus Custom… for anything else)
- ✅ Better Recents — relative timestamps + swipe-left to remove
- ✅ Meal grouping on Today (Breakfast / Lunch / Dinner / Snacks with subtotals)
- ✅ Select-all-on-focus on numeric fields — tapping a value highlights it for clean overwrite

---

## Next up — small fixes & high-leverage cleanups

### Polish that emerges from real use
You'll spot these as you use the app. Examples that are likely to bug you:
- Numbers should round better in some places (3.0 should display as 3, not 3.0)
- Barcode scanner needs a clear "tap to scan again" if it misreads
- Haptic feedback on logging actions — adds tactile confirmation
- Empty states could be friendlier (currently just "Nothing logged yet today.")
- The breakdown sheet rows could indicate which entries contributed (tap a row to see "from these foods")

### Goals UI for all 19 nutrients
Currently Settings only exposes calories/protein/carbs/fat/water goals editable in the UI. The other 14 nutrient goals are stored with sensible defaults but you can't change them. Add a "More goals" section in Settings. ~30 min.

### Entry deletion that actually undoes
Right now swipe-to-delete is permanent. iOS users expect a brief "undo" snackbar at the bottom. Saves a real "oh shit" moment when you misclick. ~20 min.

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

In rough order:
1. **Use the app for 3-5 real days** before adding any new features. The app is now genuinely usable end-to-end. Real friction will tell you what's actually missing better than any roadmap entry can.
2. **Search by name + food library** — once this exists, the app feels complete. No other v1 trackers compare.
3. **Trends view** — this is when "I've been tracking for a week" becomes "I'm noticing patterns."
4. **CSV export** — easy, adds peace of mind.
5. **Goals UI for all 19 nutrients + small polish items** — bundle these into one cleanup session.

The big ones (search, trends) are full-session efforts each. The small items in "Next up" stack well — knock 3-4 out together.
