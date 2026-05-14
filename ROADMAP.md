# LifePlanner Roadmap

LifePlanner is pivoting from a four-tab personal organizer into a productivity *farming simulator*. Real goals, habits, and tasks drive in-game progression on a SpriteKit farm. Living doc — edit freely.

## Vision

The user lands on a 2D farm. Every plot, animal pen, and orchard tree on that farm is bound to a real Goal in their life. Logging habits and finishing tasks feeds health into the matching plot; neglect causes plots to wither and eventually die. Daily quests — sourced from due/overdue tasks and pending habits — pay gold on completion. Gold expands the farm (more concurrent goals) and, later, customizes the farmer, pets, and farmhouse.

The classic Tasks / Habits / Goals tabs remain as fast direct-entry surfaces; the Farm is the new default experience and the motivator.

## Phase 1 — Pivot (v0.5.0)

The cutover release. Hard schema reset; the previous local DB is discarded on first launch. No CloudKit yet, so no remote impact.

### Removals
- [ ] Remove the Contacts tab, `DBModel.Contact`, `ContactsInteractor`, `ContactsBridge`, `ContactsTabView`, `ContactDetailView`, and the contacts-related unit tests.
- [ ] Drop `NSContactsUsageDescription` and any Contacts entitlement.
- [ ] Drop `DBModel.Contact.self` from `AppSchema`; bump schema to `Version(0, 5, 0)`.

### New data model
- [ ] `DBModel.FarmState` — singleton: gold balance, plot capacity, last decay tick.
- [ ] `DBModel.FarmPlot` — grid position, kind (crop/animal/tree/structure/commonField), health (0–100), state (empty/growing/mature/withered/dead), optional bound `Goal`.
- [ ] `DBModel.Quest` — day-keyed, slot 0–2, kind (taskDue/habitDue/commonFieldTend), referenceID, goldReward, state, rerollCount.
- [ ] `DBModel.Goal` gains `farmElementType` (default `.crop`) and an optional `plot` relationship.

### Farm tab (new default)
- [ ] `FarmTabView` hosting `SpriteView` becomes the first tab and the default `selectedTab`.
- [ ] `FarmScene` (SpriteKit) renders a tile grid sized to `FarmState.plotCapacity`, with a HUD (gold counter, quest-log button, capacity-upgrade button) and tap-to-inspect plot interaction.
- [ ] Placeholder visuals: `PlotTextureFactory` returns procedural `SKShapeNode` placeholders keyed by `(kind, state, healthBucket)`. AI-generated PNGs swap in by dropping matching imagesets into `Assets.xcassets` — no code change per asset.
- [ ] `PlotDetailSheet` (SwiftUI overlay) shows the bound goal, its linked habits/tasks, completion shortcuts, and a "Re-plant" action when dead.

### Interactors & game logic
- [ ] `EconomyInteractor` — single source of truth for `FarmState.gold`; `credit`, `spend(throws)`.
- [ ] `FarmInteractor` — singleton bootstrap (FarmState + common-field plot), `bindPlot(to: Goal)`, contribution math (habit log = +health, task complete = +health priority-scaled), daily decay tick, wither→dead transitions, `replant` (gold cost), `purchaseCapacity` (gold cost).
- [ ] `QuestInteractor` — `rollDaily` (idempotent per day; 3 slots from overdue/due tasks + pending habits, padded with commonFieldTend), `reroll` (per-slot gold cost escalating with `rerollCount`), `claim`, `expireOldQuests`, plus passive `notifyCompletion(referenceID:)` so any completion path auto-claims.
- [ ] `HabitsInteractor.logToday` and `TasksInteractor.toggleDone` hook the farm-contribution + quest-notify side effects.
- [ ] `AppLifecycleHandler` on foreground: advance daily decay against `lastDecayTick`, roll today's quests, expire yesterday's.

### Goal-create / edit
- [ ] `FarmElementType` picker (Crop / Animal / Tree / Structure) on goal create + edit.
- [ ] Over-capacity guardrail: opens `CapacityUpgradeSheet` to spend gold on `plotCapacity++`.

### Common field
- [ ] Singleton commonField plot absorbs contributions from habits/tasks not linked to any goal and emits a slow passive gold trickle when healthy.

### Tests
- [ ] `FarmInteractorTests` — bind, contribute, decay across days, wither→dead, replant cost.
- [ ] `QuestInteractorTests` — rollDaily idempotency, reroll cost escalation, claim-on-completion, expire.
- [ ] `EconomyInteractorTests` — credit / spend / insufficient-funds throw.
- [ ] `GoalsInteractorTests` extension — creating a goal allocates a matching plot; over-capacity throws.

### Verification
- [ ] `xcodebuild ... build test` green after each ordered step.
- [ ] Manual sim walkthrough: open to Farm → create goals of each type → log habits / complete tasks → see plot health rise → re-roll a quest (debit gold) → auto-claim on task completion (credit gold) → force-advance decay → wither / die / re-plant → over-capacity flow → buy plot.

## Phase 2 — Visual identity & content

Once the v0.5.0 mechanics ship, the focus moves to making the farm look and feel like a game.

- [ ] **AI-generated asset pack.** Lock palette, tile size, isometric vs. top-down. Generate per-state sprites for each `FarmElementType`. Each sprite drops into `Assets.xcassets` under the existing `AssetKeys` names — no code change required.
- [ ] **Animation passes.** Idle wiggle / sway, contribution feedback (sparkle on health gain), wither shake, death dissolve.
- [ ] **Ambient farm life.** Background NPCs (butterflies, birds) — pure flavor, no gameplay tie.
- [ ] **Sound.** Light SFX on contribution / quest claim / re-roll. Optional ambient loop.

## Phase 3 — Cosmetics economy

Expand gold sinks beyond capacity.

- [ ] **Farmer avatar customization.** Hats, outfits. Avatar wanders the farm idle path.
- [ ] **Pets.** Unlockable companions that wander the farm. Pure flavor; no goal binding.
- [ ] **Farmhouse cosmetics.** Roof colors, decor, exterior expansions.
- [ ] **Cosmetic shop UI** reached from the HUD.

## Phase 4 — Depth & retention

- [ ] **Streaks → seasonal events.** Consecutive-day habit streaks unlock limited-time decorations.
- [ ] **Quest variety.** Multi-step quests, weekly quests, themed chains (e.g., "harvest 5 mature crops this week").
- [ ] **Difficulty / reward tuning.** Telemetry-driven adjustments to gold rewards, decay rate, capacity costs.
- [ ] **Notifications.** Re-introduce task-due notifications (carry-over from old roadmap) plus farm-health alerts ("Your Crop is wilting").

## Phase 5 — Platform

- [ ] **iCloud sync.** Schema is already CloudKit-compatible. Flip the entitlement and switch to `ModelConfiguration(cloudKitDatabase:)`. Requires paid Apple Developer account.
- [ ] **WidgetKit.** Today's quests widget; farm-snapshot widget.
- [ ] **App Intents / Shortcuts.** "Roll today's quests", "Mark habit done", "Show farm".
- [ ] **Spotlight.** Tasks searchable from system search.

## Deferred / explicitly out of scope for v0.5.0

- SwiftData migration (hard reset chosen for the v0.4.0 → v0.5.0 cutover; pre-existing local data is discarded).
- Cosmetic systems (farmer, pets, farmhouse) — see Phase 3.
- AI-generated final art — placeholder phase ships first; see Phase 2.
- Habit weekly/custom cadence and target counts (carry-over from old roadmap; revisit after pivot lands).
- Goal sub-goals & metric tracking (carry-over; revisit after pivot lands).
