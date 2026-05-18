# Tiller Roadmap

Tiller is pivoting from a four-tab personal organizer into a productivity *farming simulator*. Real goals, habits, and tasks drive in-game progression on a SpriteKit farm. Living doc — edit freely.

## Vision

The user lands on a 2D farm. Every plot, animal pen, and orchard tree on that farm is bound to a real Goal in their life. Logging habits and finishing tasks feeds health into the matching plot; neglect causes plots to wither and eventually die. Daily quests — sourced from due/overdue tasks and pending habits — pay gold on completion. Gold expands the farm (more concurrent goals) and, later, customizes the farmer, pets, and farmhouse.

The classic Tasks / Habits / Goals tabs remain as fast direct-entry surfaces; the Farm is the new default experience and the motivator.

## Phase 1 — Pivot (v0.5.0) ✓

The cutover release. Hard schema reset; the previous local DB is discarded on first launch. No CloudKit yet, so no remote impact.

### Removals
- [x] Remove the Contacts tab, `DBModel.Contact`, `ContactsInteractor`, `ContactsBridge`, `ContactsTabView`, `ContactDetailView`, and the contacts-related unit tests.
- [x] Drop `NSContactsUsageDescription` and any Contacts entitlement.
- [x] Drop `DBModel.Contact.self` from `AppSchema`; bump schema to `Version(0, 5, 0)`.

### New data model
- [x] `DBModel.FarmState` — singleton: gold balance, plot capacity, last decay tick.
- [x] `DBModel.FarmPlot` — grid position, kind (crop/animal/tree/structure/commonField), health (0–100), state (empty/growing/mature/withered/dead), optional bound `Goal`.
- [x] `DBModel.Quest` — day-keyed, slot 0–2, kind (taskDue/habitDue/commonFieldTend), referenceID, goldReward, state, rerollCount.
- [x] `DBModel.Goal` gains `farmElementType` (default `.crop`) and an optional `plot` relationship.

### Farm tab (new default)
- [x] `FarmTabView` hosting `SpriteView` becomes the first tab and the default `selectedTab`.
- [x] `FarmScene` (SpriteKit) renders a tile grid sized to `FarmState.plotCapacity`, with a HUD (gold counter, quest-log button, capacity-upgrade button) and tap-to-inspect plot interaction.
- [x] Placeholder visuals: `PlotTextureFactory` returns procedural `SKShapeNode` placeholders keyed by `(kind, state, healthBucket)`. AI-generated PNGs swap in by dropping matching imagesets into `Assets.xcassets` — no code change per asset.
- [x] `PlotDetailSheet` (SwiftUI overlay) shows the bound goal, its linked habits/tasks, completion shortcuts, and a "Re-plant" action when dead.

### Interactors & game logic
- [x] `EconomyInteractor` — single source of truth for `FarmState.gold`; `credit`, `spend(throws)`.
- [x] `FarmInteractor` — singleton bootstrap (FarmState + common-field plot), `bindPlot(to: Goal)`, contribution math (habit log = +health, task complete = +health priority-scaled), daily decay tick, wither→dead transitions, `replant` (gold cost), `purchaseCapacity` (gold cost).
- [x] `QuestInteractor` — `rollDaily` (idempotent per day; 3 slots from overdue/due tasks + pending habits, padded with commonFieldTend), `reroll` (per-slot gold cost escalating with `rerollCount`), `claim`, `expireOldQuests`, plus passive `notifyCompletion(referenceID:)` so any completion path auto-claims.
- [x] `HabitsInteractor.logToday` and `TasksInteractor.toggleDone` hook the farm-contribution + quest-notify side effects.
- [x] `AppLifecycleHandler` on foreground: advance daily decay against `lastDecayTick`, roll today's quests, expire yesterday's.

### Goal-create / edit
- [x] `FarmElementType` picker (Crop / Animal / Tree / Structure) on goal create + edit.
- [x] Over-capacity guardrail: opens `CapacityUpgradeSheet` to spend gold on `plotCapacity++`.

### Common field
- [x] Singleton commonField plot absorbs contributions from habits/tasks not linked to any goal and emits a slow passive gold trickle when healthy.

### Tests
- [x] `FarmInteractorTests` — bind, contribute, decay across days, wither→dead, replant cost.
- [x] `QuestInteractorTests` — rollDaily idempotency, reroll cost escalation, claim-on-completion, expire.
- [x] `EconomyInteractorTests` — credit / spend / insufficient-funds throw.
- [x] `GoalsInteractorTests` extension — creating a goal allocates a matching plot; over-capacity silently skips bind.

### Verification
- [x] `xcodebuild ... build test` green after each ordered step.
- [x] Manual sim walkthrough: open to Farm → create goals of each type → log habits / complete tasks → see plot health rise → re-roll a quest (debit gold) → auto-claim on task completion (credit gold) → force-advance decay → wither / die / re-plant → over-capacity flow → buy plot.

## Phase 2 — Visual identity & content

Once the v0.5.0 mechanics ship, the focus moves to making the farm look and feel like a game.

- [ ] **AI-generated asset pack.** Lock palette, tile size, isometric vs. top-down. Generate per-state sprites for each `FarmElementType` (25 imagesets: 5 kinds × 5 states) plus `hud_gold_icon`. Each sprite drops into `Assets.xcassets` under the `AssetKeys`-defined names — no code change required.
- [x] **Animation passes.** Idle wiggle / sway, contribution feedback (sparkle on health gain), wither shake, death dissolve.
- [x] **Ambient farm life.** Background NPCs (butterflies, birds) — pure flavor, no gameplay tie.
- [ ] **Sound.** `SoundPlayer` scaffolding is wired (`sfx_contribution`, `sfx_quest_claim`, `sfx_quest_reroll`, `sfx_farm_ambience`). Remaining work: source or generate the four audio files and add them to the bundle. No code changes needed.

## Phase 3 — Cosmetics economy ✓

Expand gold sinks beyond capacity.

- [x] **Farmer avatar customization.** Hats, outfits. Avatar wanders the farm idle path. `AvatarController` + `CosmeticCatalog` hats/outfits.
- [x] **Pets.** Unlockable companions that wander the farm. Pure flavor; no goal binding. `PetController` with dog, cat, sheep procedural sprites.
- [x] **Farmhouse cosmetics.** Roof colors, decor, exterior expansions. `FarmhouseNode` with red/blue roof + flower-box variants.
- [x] **Cosmetic shop UI** reached from the HUD. `CosmeticShopView` (segmented by kind, buy/equip/unequip per row). `DBModel.OwnedCosmetic` persists ownership; `CosmeticInteractor` handles gold debits and equipped-slot invariant. Schema bumped to v0.6.0.

## Phase 4 — Depth & retention

- [x] **Streaks.** `currentStreak` / `longestStreak` / `lastStreakMilestone` on `DBModel.Habit` (schema v0.7.0). Recomputed in `HabitsInteractor.toggleDone` as the consecutive chain ending at the toggled day. Milestone gold bonuses at 7 / 14 / 30 / 60 / 100 days (`StreakTuning`); each milestone credited once and announced via an immediate local notification. `🔥 N` streak badge shows in `HabitsTabView` when ≥ 2.
- [x] **New quest kind: `harvestMature`.** "Grow 2+ mature plots simultaneously" (🌾). Rolled when ≥2 living goal plots exist; auto-claimed by `QuestInteractor.checkFarmQuests`, which is called from both `HabitsInteractor.toggleDone` and `TasksInteractor.toggleDone` after any farm contribution. Reward: 🪙 15.
- [x] **Farm-health notifications.** `NotificationScheduler` gains `schedulePlotAlert` (next-morning calendar trigger) and `cancelPlotAlert`. `FarmInteractor.decay` fires a wither alert on the `.growing → .withered` transition and a death alert on `.withered → .dead`; `replant` cancels the pending alert. Streak milestone fires a one-shot immediate notification on each milestone hit.
- [x] **Quest variety (further).** Weekly harvest quest (slot 3, ISO-week key): push 5 plots to mature this week for 🪙 30. `QuestKind.weeklyHarvest` with `progress`/`progressTarget` fields on `DBModel.Quest` (schema v0.8.0). `QuestInteractor.rollWeekly` (idempotent per week) called from daily tick; `trackMatureTransitions` called from Habits/Tasks after every farm contribution. `QuestLogView` gains a "This Week" section with a `ProgressView`.
- [ ] **Difficulty / reward tuning.** Telemetry-driven adjustments to gold rewards, decay rate, capacity costs. Deferred — requires analytics backend.

## Phase 5 — Platform

- [ ] **iCloud sync.** Schema is already CloudKit-compatible. Flip the entitlement and switch to `ModelConfiguration(cloudKitDatabase:)`. Requires paid Apple Developer account.
- [x] **WidgetKit.** Today's quests widget scaffold in `QuestsWidget/` (`QuestEntry`, `QuestProvider`, `QuestsWidgetView`, `QuestsWidgetBundle`). Remaining: add Widget Extension target in Xcode, enable App Groups on both targets, update `ModelContainer.appModelContainer()` to use the shared group URL.
- [x] **App Intents / Shortcuts.** `ShowFarmIntent`, `RollTodaysQuestsIntent`, `MarkHabitDoneIntent` (performs background SwiftData write — no app open needed). `HabitEntity` + `HabitEntityQuery` for parameter resolution. `TillerShortcuts: AppShortcutsProvider` registers all three with Siri and the Shortcuts app.
- [x] **Spotlight.** `SpotlightIndexer` actor indexes open tasks via `CoreSpotlight`; wired into `TasksInteractor` (add/update/done/delete). `SystemEventsHandler` calls `reindexAll` on every foreground.

## Phase 6 — Carry-over polish

Items that were punted during the pivot to keep v0.5.0 focused.

- [x] **Habit weekly cadence + target counts.** `HabitFrequency.weekly` with `weeklyTarget: Int` on `DBModel.Habit` (schema v0.9.0). `isWeekComplete(containing:)` helper used by quest pool (weekly habits drop out of daily quests once the target is met). Weekly streak = consecutive completed ISO weeks ending at *the current week*, with a mid-week grace pass so backfills don't reset progress. `AddHabitSheet` has a stepper for 1–7×/week; `HabitsTabView` row shows "Weekly · 2/3" badge.
- [x] **Goal sub-goals & metric tracking.** New `DBModel.SubGoal` model with cascade-delete on the parent (`subGoals` relationship + `order` field for stable display). Checking a sub-goal pumps `taskBaseContribution` health into the parent's plot. New optional metric fields on `DBModel.Goal`: `metricUnit`, `metricTarget`, `metricValue` (schema v0.10.0). `GoalsInteractor.logMetricProgress` adds to the value and contributes habit-magnitude health to the plot. `GoalDetailView` gets a "Sub-goals" section with inline add + swipe delete, and a "Progress" section showing value/target with a ProgressView and a log sheet.

## Phase 7 — Polish & retention

Productivity-app maturity work. Closing the gap from "playable in TestFlight" to "I'd recommend this to a friend." All items are implementable today; no external blockers.

- [ ] **Stats / Insights screen.** New surface showing aggregate data: per-habit completion rate over the last 30 / 90 days (SwiftUI Charts line chart), per-goal contribution totals, longest streak per habit, total tasks completed, total gold earned, plots that have ever died (regret meter). Drives self-reflection and motivates streaks. Pure SwiftData queries — no schema change needed.
- [ ] **Onboarding flow.** First-launch carousel (TabView with `.page` style) introducing the farm metaphor: farm = your goals, plots = goals, habits/tasks pump health, quests pay gold, neglect kills plots. Skip-able. Persist `hasCompletedOnboarding: Bool` on `FarmState`. 4–6 pages with illustrations.
- [ ] **Settings screen.** Gear-icon entry from any tab. Sections: Notifications (master toggle + per-type for plot alerts / habit reminders / streak milestones), Data (export all data as JSON, import from JSON, reset farm), About (version, links to docs/asset-spec.md once external). Uses the existing notification permission flow; no new schema.
- [ ] **Recurring tasks.** Tasks are single-shot today. Add `recurrence: TaskRecurrence?` (`.daily`, `.weekly`, `.weekdays`, `.custom([weekday])`). On `toggleDone`, if the task has a recurrence, the next occurrence is auto-created with a bumped `dueDate`. Schema bump. Updates `AddTaskSheet` UI.
- [ ] **Accessibility audit.** VoiceOver labels on every farm sprite, plot-health bar, and quest row. Dynamic Type support throughout (no hard-coded `.caption` sizes that don't scale). Contrast check on placeholder farm colors. Respect `UIAccessibility.isReduceMotionEnabled` for farm animations.
- [ ] **iPad layout pass.** Currently renders but isn't optimized — `NavigationSplitView` for tab layout, larger farm scene, two-pane goal detail.
- [ ] **Dark mode pass.** Verify every view (esp. SpriteKit-backed) reads cleanly in dark mode. Adjust placeholder farm colors if contrast slips.

## Phase 8 — Farm-sim depth

Game-y systems that layer on top of the productivity core to keep long-term users engaged. Each is independent of the others; ship in any order.

- [ ] **Seasons.** Real-world calendar maps to spring / summer / fall / winter visuals. Farm scene tints + ambient particle effects change at each transition. Optional: per-season passive modifier (e.g. winter doubles decay for non-evergreens). `Season` enum derived from `Date`; no schema needed.
- [x] **Weather events.** Periodic 24-hour weather episodes — rain doubles habit contribution, drought halves task contribution, sunshine pays passive gold. Surfaced via a small HUD icon + tap-to-explain. New `DBModel.WeatherEvent { kind, startedAt, expiresAt }`. Schema bump.
- [x] **Achievements.** Meta-rewards for milestones: "Logged 100 habits", "First 30-day streak", "Owned 5 cosmetics", "Reached year 1 of farming", "First plot revived from dead". Surfaced via a trophy-shelf view + immediate local notification on first unlock. New `DBModel.Achievement { slug, unlockedAt }`. Catalog defined in code; rule evaluation hooks into existing toggle/claim paths.
- [ ] **Goal templates.** Pre-built goal templates ("Run a 5K", "Read 12 books", "Save $5K") so new users get a fast start without staring at an empty Goals tab. Static catalog + an "Add from template" button on the empty-state view. No schema change.
- [x] **Tool upgrades.** Buy-with-gold farm tools that boost contribution magnitudes (better watering can = +5 to habit contribution; sharper hoe = +5 task contribution). New `DBModel.OwnedTool` mirroring `OwnedCosmetic`. Schema bump.

## Phase 9 — App Store launch prep

The work between "TestFlight beta with 5 friends" and "public listing on the App Store."

- [ ] **Privacy policy & terms.** Static webpages, linked from Settings → About and the App Store listing. Local-only data simplifies this — no third-party data collection to disclose.
- [ ] **Crash reporting.** Either integrate Sentry (or similar) behind a small wrapper, or formalize the Xcode-built-in crash-log flow via TestFlight feedback.
- [ ] **App Store screenshots & description.** Generate 6.5" / 6.1" iPhone screenshots for the marketing slots: Farm, Tasks, Habits, Goal detail with metric, Quest log, Cosmetic shop. Description copy, keywords, category selection.
- [ ] **Real-device QA pass.** Run every interaction on a physical iPhone, including notifications, App Intents from Siri, Spotlight search results. Catch issues simulators miss.
- [ ] **Performance pass.** Instruments time-profile the farm scene during heavy animation (multiple plots animating + ambient life NPCs). Time-profile SwiftData queries against a 6-month-old account simulation (1000+ habit log entries) to catch any quadratic surprises.

## Deferred / explicitly out of scope for v0.5.0

- SwiftData migration (hard reset chosen for the v0.4.0 → v0.5.0 cutover; pre-existing local data is discarded).
- Cosmetic systems (farmer, pets, farmhouse) — see Phase 3.
- AI-generated final art — placeholder phase ships first; see Phase 2.
