# FoodJournal — Roadmap

A pragmatic, ranked plan for what comes after v1.1. Items higher on the list have higher value-per-hour-of-work; items lower down are nice but optional. The ranking inside each section is from your stated priorities, with adjustments where bug fixes make more sense first.

---

## Next up — small fixes (do these before more features)

These are quick, high-leverage cleanups that will pay off every day you use the app.

### Fix the water −8 button
Currently `logWater(-8)` deletes the most recent entry, which is destructive if that entry was a custom 48 oz log. Change it to always insert a negative entry. Then add a "today's water entries" sheet (tappable from the water card) where you can delete specific entries. Probably 30 minutes of work.

### Edit an existing food entry
Right now if you log a chicken sandwich at 1 serving and realize it was 1.5, you have to delete and re-add. Add tap-to-edit on Today tab entries — opens a sheet that lets you change servings count and meal type. Reuse the `RelogSheet` UI we already built. ~30 minutes.

### Better Recents
Two small improvements:
1. Show "Last logged: yesterday at 8am" or similar so it's easier to recognize what you're picking
2. Long-press to delete from recents (in case something embarrassing or one-time gets stuck there)

### Polish small things as you find them
You'll spot these naturally as you use the app. Examples that are likely to bug you:
- Numbers should round better in some places (3.0 should display as 3, not 3.0)
- The barcode scanner doesn't have a clear "tap to scan again" if it misreads
- No haptic feedback when you tap +12 oz of water (a little tap would feel right)

---

## Tier 1 — Will improve daily use most

### Search by name (USDA FoodData Central)
For fresh produce and whole foods that don't have barcodes — apples, chicken breast, broccoli. USDA has a free API with ~400k foods. Add a "Search" option on the Add tab. Hardest part is dealing with their multiple "branded" / "foundation" / "survey" food types and picking sensible defaults.

Roughly 1-2 hours to a working v1. Can be polished later.

### Weekly trends chart
A new tab (or pull-up sheet from Today) that shows last 7 days: calories, each macro, water, all on small line charts. Apple's `Charts` framework makes this surprisingly fast to build. Useful for noticing patterns ("oh, weekends are way over goal").

~1 hour using SwiftUI Charts.

### Entry deletion that actually undoes
Right now swipe-to-delete is permanent. iOS users expect a brief "undo" snackbar at the bottom. Small change but feels much more polished and saves a real "oh shit" moment.

---

## Tier 2 — Useful but not urgent

### iCloud sync across devices
Convert SwiftData container to use CloudKit. Your data syncs to your other Apple devices automatically. Comes with edge cases (conflicts, offline, a free Apple ID limits CloudKit usage). Worth doing only if you actually use a second device — iPad, Mac, etc. Probably 1-2 hours including testing.

### Better photo logging
Several improvements possible:
- Take photo directly in-app instead of only picking from library
- Show the photo as a thumbnail on the logged entry so you can see what you ate later
- Re-prompt Claude with "are you sure?" if confidence is low
- Cache the photo locally so you can look at history later
- Multi-photo support — sometimes one angle isn't enough

### Meal grouping on Today
Right now everything is one flat list. Group by Breakfast / Lunch / Dinner / Snack with running subtotals per meal. Helps you see what's eating your calorie budget. ~30 min.

### Notification reminders
Optional reminder to log dinner at 8pm if you haven't logged anything in 4 hours, etc. Apple's `UserNotifications` framework. Get this wrong and it's annoying — get it right and you actually use the app daily. Worth experimenting with.

### Smart auto-fill defaults
If you eat the same breakfast every weekday, the app should know that. After 2 weeks of data, suggest "Log your usual?" Tier 3 ML, but you can do a basic version in 30 min by just looking at "what did the user log between 7-10am yesterday."

---

## Tier 3 — Polish & advanced

### UI polish across the board
- Custom app icon
- Animated number transitions (your calorie ring smoothly counting up when you add an entry)
- Better empty states with illustrations
- Dark mode tuning (the app inherits system dark mode but some colors could be tweaked)
- Custom typography — the app is very system-default right now, has room for personality

### Macros breakdown by meal
Show how each macro is distributed across breakfast/lunch/dinner. Helps with timing (e.g., "I keep eating 80% of my carbs at dinner").

### Weight tracking
Stretch goal — you mentioned in v1 planning that exercise + weight wasn't a priority, but a simple weight log tab is easy to add and pairs well with the trends chart.

### Export your data
A "Settings → Export" button that emails you a CSV of all your entries. Handy if you ever want to migrate or share with a nutritionist. ~20 min.

### Apple Health integration
Two-way sync with Apple Health — Health gets your calorie/macro/water totals, you get weight and exercise from Health. Lots of edge cases but unlocks the "real" iOS experience. Probably 2-3 hours.

### Recipe support
"I made this stir-fry with chicken, rice, broccoli, soy sauce." Save the combination as a named recipe so you can log it as one item next time. Multiple ways to model this — simplest is "a recipe is just a saved meal of multiple FoodEntry rows that get inserted together."

### Real OCR of nutrition labels
Photo of nutrition facts panel → parsed into a CachedFood entry. Claude can already do this with the existing photo flow, just needs a different prompt and a UI route. Fills the Open Food Facts gap nicely.

### Public release
If the app gets good enough to share: paid Apple Developer account ($99/year), App Store Connect setup, screenshots, privacy policy, marketing site. A few-day project on its own. The code's already structured well enough that this isn't a big lift technically — the work is all in the surrounding artifacts.

---

## What I'd do next if I were you

In order:
1. **Fix the −8 water bug** (you'll hit this every day until it's fixed)
2. **Edit existing food entries** (this is the one missing primitive that makes the app feel real)
3. **Search by name with USDA** (massively expands what you can log easily)
4. **Use the app for a real week** before adding anything else — see what actually annoys you

Resist the urge to keep building. Real usage tells you what to build next better than any roadmap.
