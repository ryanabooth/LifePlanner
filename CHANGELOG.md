# Changelog

All notable changes to Tiller are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

### Fixed
- The habit history calendar's month navigation now works. Embedded in the editor's List, the prev/next chevrons were swallowed by the row; making them borderless buttons restores paging

### Added
- Common field plot detail now has a "create new" button on its Habits and Tasks section headers, mirroring goal plots (new items are unlinked, so they feed the common field)
- Manual task ordering — tap Edit on the Tasks list to drag tasks into a custom order. The order applies as a tiebreaker *after* the active sort field (due date / priority), so dragging rearranges tasks that share the same due date or priority. Schema bumped to v0.17.0

### Changed
- The habit history calendar is now shown directly in the habit editor instead of behind a "View history" tap

### Fixed
- Back-filling a habit for a past day (the once-a-day catch-up prompt) no longer triggers today's farm contributions or quest completion — it only records the entry and updates the streak
- Closing the task editor now always returns to the Tasks tab. A task-due notification could open the editor over the farm view, leaving you stranded there after saving
- Tapping a habit reminder now opens the Habits list (scrolled to that habit) so it can be marked done, instead of opening the edit form where logging isn't possible
- Paused goals no longer decay — a plot bound to a paused goal is exempt from the daily health loss until the goal is resumed
- Habit streak indicators now reset after a missed day. Streaks are recomputed on launch, so a habit that lapsed no longer shows a stale 🔥 count until the next time you log it

## [Build 19] — pending TestFlight

### Added
- **Weekdays habit cadence** — habits can now repeat Monday–Friday only. Weekends don't break the streak (Fri→Mon counts as consecutive) and don't nag. Reminders for weekdays habits fire Mon–Fri only. Schema bumped to v0.16.0
- **Reminder time on the habits list** — habits with a reminder now show the time next to the bell icon in the second row (was just the bell icon)
- **Deep links from notifications** — tapping a habit reminder opens that habit's editor, a task due alert opens that task's editor, and a farm plot alert switches to the Farm tab
- **Habit history calendar** — the habit editor now has a "View history" link showing a month-grid calendar of completed days, with month paging and a streak badge
- **End-of-day streak reminder** — opt-in daily evening nudge (Settings → Notifications, default 8 PM) to log habits before the day ends
- **Back-fill missed habits** — on the first app open each day, a prompt lists habits that were due on their most recent scheduled day but weren't logged (for the late-night flosser who forgets), letting you check them off retroactively so streaks stay intact. Weekdays-only habits correctly look back past the weekend (a habit missed Friday surfaces on Monday)

### Fixed
- Un-logging a habit now correctly decreases its streak. SwiftData wasn't pruning the deleted entry from the in-memory relationship, so the streak previously stayed put when you reversed a completion

### Changed
- Withering now lasts 1 day before a plot dies (was 3), so neglect has faster consequences
- Dead plots now block linked habit/task completion in the plot detail view until replanted, with a "Re-plant this plot to resume…" note (contributions already no-op'd on dead plots; this makes it visible)

### Fixed
- Phantom second "Common Field" — launch-time reconcile now removes orphaned user plots (no bound goal) and any duplicate common-field rows left behind by the earlier harvest bug. Any plot without a goal had been rendering as an extra "Common Field"

## [Build 18] — 2026-05-28

### Fixed
- Harvested plot appeared as a second Common Field — plot is now deleted from the model context on harvest, freeing the capacity slot and removing it from the farm scene immediately
- Harvest button required manually setting goal status to Done — button now appears automatically when all linked tasks are complete

---

## [Build 17] — 2026-05-28

### Added
- **Harvest / retire a completed goal's plot** — when all linked tasks are done, a "Goal complete!" banner appears at the top of the plot detail with a Harvest button. Awards gold scaled to plot health (base 30 + up to 20 bonus); goal is kept in Goals tab for records
- **Common field now lists unlinked tasks and habits** — tapping the common field plot shows all unlinked habits and incomplete tasks that feed it, with the same toggle-to-complete UX as goal plots
- **Vacation mode** — Settings → Farm toggle pauses daily plot health decay; the tick still advances so returning doesn't cause a multi-day catch-up penalty
- **Quick link / create buttons on plot detail** — linked Habits and Tasks section headers now have link-existing (🔗) and create-new (➕) icon buttons, matching the Goal detail view

### Changed
- **Streak badge redesigned** — replaced small `🔥 N` caption text with a prominent trailing `flame.fill` badge in orange at subheadline weight; badge now appears from streak = 1 (was ≥ 2)
- **Incomplete tasks and habits sort to the top** in both Goal detail and Plot detail views
- **Replant button shows for withered plots** (not just dead) — a withered plot at 0 health offers no other recovery action; section header reads "Plot is withering" vs "Plot died" accordingly
- **Replant / harvest section moved to top of plot detail** when the plot is in a critical state

### Fixed
- Weekly quest was expiring mid-week — weekly quests now compare against the current week-start rather than today
- Tapping a task or habit row in the link picker required hitting the label exactly — `.contentShape(Rectangle())` applied to all interactive rows

---

## [Build 16] — 2026-05-27

### Removed
- **Sub-goals removed** — the sub-goals section and `DBModel.SubGoal` model have been removed; use linked Tasks for goal checklists instead (schema v0.15.0)
- **Tags removed from Task model** — unused `tags: [String]` field removed (schema v0.14.0)

### Added
- **Quick link / create buttons on Goal detail** — Habits and Tasks section headers now have link-existing and create-new icon buttons; create opens the add sheet with the goal pre-filled
- **Linked goal in data export** — JSON export now includes `linkedGoalID` and `linkedGoalTitle` on each task and habit

### Fixed
- Duplicate habit reminders reconciled on launch — stale `habit-*` notification identifiers are cancelled at startup to prevent orphaned requests accumulating across builds
- "Edit Goal" button moved to trailing position in plot detail toolbar
- Habits section now appears before Tasks section in plot detail view (consistent with Goal detail ordering)
- Default task due date now defaults to today (not tomorrow) with no time component
- Goal picker moved above due date in the add-task form
- Completed tasks hidden from the link-task picker (only incomplete tasks + already-linked tasks shown)

---

## [Build 15] — 2026-05-18

### Added
- **Stats / Insights screen** — completion rate charts (30/90 day), per-goal contribution totals, streak bars, total tasks completed, total gold earned
- **Onboarding flow** — first-launch carousel introducing the farm metaphor; skippable; persisted to `FarmState.hasCompletedOnboarding`
- **Settings screen** — notifications (per-type toggles + OS settings link), data export/reset, About section
- **Recurring tasks** — tasks can repeat daily / weekly / weekdays; next occurrence auto-created on completion
- **Accessibility audit** — VoiceOver labels on all farm sprites, plot health bars, quest rows; reduce-motion support throughout
- **iPad layout** — `NavigationSplitView` for tab layout, two-pane goal detail, larger farm scene
- **Dark mode pass** — all views verified in dark mode, SpriteKit colors adjusted for contrast

---

## [Build 14] — 2026-05-11

### Added
- **Seasons** — real-world calendar maps to spring/summer/fall/winter; farm scene tints + ambient particles change at each transition
- **Weather events** — 24-hour episodes (rain doubles habit contribution, drought halves task contribution, sunshine pays passive gold); HUD icon with tap-to-explain
- **Achievements & trophy shelf** — milestones for logged habits, streaks, cosmetics, farming years, and plot revivals; local notification on first unlock
- **Goal templates** — pre-built goals ("Run a 5K", "Read 12 books", "Save $5K") on empty Goals tab
- **Tool upgrades** — buy-with-gold tools that boost habit and task contribution magnitudes
- **Quest badge** — badge count on the quest-log button when claimable quests are available

### Fixed
- Farm plot tab bar visibility
- Weekly quest Monday edge-case in tests

---

## [Build 13] — 2026-05-04

### Added
- **Cosmetics economy** — farmer avatar (hats, outfits), pets (dog, cat, sheep), farmhouse cosmetics (roof colors, decor); cosmetic shop UI; `DBModel.OwnedCosmetic` (schema v0.6.0)
- **Streaks** — `currentStreak` / `longestStreak` on `DBModel.Habit` (schema v0.7.0); milestone gold bonuses at 7/14/30/60/100 days; streak milestone notifications
- **Weekly harvest quest** — "Push 5 plots to mature this week" (schema v0.8.0); `QuestLogView` "This Week" section with progress bar
- **Habit weekly cadence** — `HabitFrequency.weekly` with `weeklyTarget`; weekly streak; `AddHabitSheet` stepper (schema v0.9.0)
- **Goal metric tracking** — optional `metricUnit` / `metricTarget` / `metricValue` on `DBModel.Goal`; log-progress sheet; metric progress view (schema v0.10.0)
- **App Intents / Shortcuts** — `ShowFarmIntent`, `RollTodaysQuestsIntent`, `MarkHabitDoneIntent`; Spotlight indexing for open tasks
- **WidgetKit scaffold** — `QuestsWidget` extension with `QuestEntry`, `QuestProvider`, `QuestsWidgetView`

---

## [Build 12] — 2026-04-27

### Added
- **Farm Phase 1** — `FarmTabView` + `FarmScene` (SpriteKit); plot grid; gold HUD; quest log; `FarmInteractor` (bind, contribute, decay, replant); `QuestInteractor` (roll, reroll, claim, expire); `EconomyInteractor`
- **AI-generated asset pack** — per-state sprites for each `FarmElementType`; isometric tile style
- **Animations** — idle wiggle, contribution sparkle, wither shake, death dissolve, ambient butterflies/birds
- **Sound** — `SoundPlayer` scaffolding wired for contribution, quest claim/reroll, and farm ambience
- **Farm-health notifications** — wither and death alerts scheduled at next morning; cancel on replant

---

## [Build 11] and earlier

Initial TestFlight builds establishing the app foundation: Tasks, Habits, Goals tabs; SwiftData schema; notification scheduling; task sorting and filtering.
