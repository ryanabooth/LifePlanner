# Tiller — Claude Code instructions

iOS 18+ productivity-farming-sim. SwiftUI + SwiftData + SpriteKit. Habits, tasks, and goals drive growth on a 2D farm; daily quests pay gold.

## Build & test

```bash
xcodebuild -scheme LifePlanner -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' -configuration Debug build test
```

Always run the full `build test` after touching models, interactors, or anything in `Repositories/`. The destination string is finicky — `iPhone 16` no longer exists in this Xcode; use `iPhone 17`. Test output is voluminous; pipe through `grep -E "TEST SUCCEEDED|TEST FAILED|error:|failed"` for fast triage.

## Branching workflow

Never commit directly to `main`. Every change — feature, fix, doc tweak — gets its own branch (`feature/<name>`, `fix/<name>`, `docs/<name>`, `infra/<name>`), pushed, and lands via a PR with **Summary + Test plan** sections. Use `gh pr create` + `gh pr merge --merge`.

## Architecture

```
View (@Query reads)        ← SwiftUI, displays SwiftData rows reactively
   ↓
Interactor (mutations)     ← business logic, the only thing that mutates
   ↓
ModelContext               ← SwiftData; saveQuietly() after every user-facing mutation
```

- Views declare reads with `@Query`. Never mutate from views directly — always call an interactor.
- Interactors are injected via `@Environment(\.injected)` (a `DIContainer`). The container holds `Interactors` (real impls in `AppEnvironment.bootstrap`, no-op `Stub*` versions for previews/tests).
- All models live under the `DBModel` namespace (`DBModel.Habit`, `DBModel.Quest`, etc.). The `DBModel` enum in `AppSchema.swift` is just a namespace.

## Persistence rules

**Every user-facing mutation must call `context.saveQuietly()` before returning.** SwiftData's periodic autosave is timing-sensitive — an app kill or rapid context teardown after `insert` can lose the row, and `@Query` can lag past a UI snapshot if the change hasn't been committed. This bit us once already (see git history for "Fix: persist mutations immediately"). The helper lives in `Repositories/Database/ModelContext+Save.swift`.

```swift
func add(_ draft: GoalDraft, in context: ModelContext) {
    context.insert(goal)
    try? farm.bindPlot(to: goal, in: context)
    context.saveQuietly()   // ← required
}
```

## Schema versioning

Schema version is set in `LifePlanner/Repositories/Models/AppSchema.swift`. **Bump for any model change.** Currently `0.9.0`.

CloudKit-compatible rules (we're CloudKit-ready even though sync is deferred — don't break this):
- No `@Attribute(.unique)`
- Every property has a default (`var foo: Int = 0`, not `var foo: Int`)
- Every relationship is optional and has an explicit inverse
- Add a new model: define it under `DBModel.*`, add to `Schema.appSchema` array, bump version

## Project layout

```
LifePlanner/
├── AppIntents/         Siri / Shortcuts actions + entity queries
├── Core/               App entry point, SystemEventsHandler (daily tick), AppDelegate
├── DependencyInjection/  DIContainer, AppEnvironment.bootstrap
├── Interactors/        Tasks, Habits, Goals, Farm, Quests, Economy, Cosmetic
├── Repositories/
│   ├── Database/       ModelContainer config, ModelContext+Save
│   ├── Models/         All @Model classes, AppSchema
│   ├── Notifications/  NotificationScheduler protocol + real/stub
│   └── SpotlightIndexer.swift
├── UI/
│   ├── Farm/           SpriteKit scene + SwiftUI overlays
│   ├── Tasks/  Habits/  Goals/
│   └── MainTabView.swift
├── Utilities/          SoundPlayer, asset helpers
└── Resources/          Assets.xcassets, Info.plist
QuestsWidget/           Widget extension scaffold (target not added in Xcode yet)
UnitTests/              Single LifePlannerTests.swift — all tests
scripts/                testflight.sh, ExportOptions.plist; .env is gitignored
```

## Testing patterns

All tests live in `UnitTests/LifePlannerTests.swift` (one file by design — keeps the test surface visible). Use:

- `makeFarmContext()` — in-memory `ModelContext` with every SwiftData type registered. Default for farm/quest/habit tests.
- `FakeNotificationScheduler` — actor capturing scheduled/cancelled notifications for assertion.
- `Stub*Interactor` — pass these when an interactor isn't under test, to isolate the unit.
- `RealQuestInteractor(rng: { 0 })` — inject a deterministic RNG for quest-pool shuffle tests.

## Farm / quest mental model

- A **Goal** auto-binds a `FarmPlot` on creation (if plot capacity isn't exhausted).
- Habits/tasks linked to a goal pump health into that plot when completed; unlinked completions feed the singleton common-field plot.
- `QuestInteractor.rollDaily` is **idempotent per ISO day** — once today's batch is rolled, it stays. The `refreshTodaysCommonFieldSlots` method auto-upgrades `.commonFieldTend` placeholders to real task/habit candidates when they become available; this is called from `add` paths so new items appear in the quest log immediately.
- `rollWeekly` rolls the slot-3 "harvest 5 plots this week" quest, idempotent per ISO week.
- Task and habit completion paths (`toggleDone`) chain through farm + quest side effects: `farm.applyXCompletion` returns newly-matured count → `quests.trackMatureTransitions` → `quests.checkFarmQuests` → `quests.notifyCompletion`. Saving once at the end commits everything.

## TestFlight

`scripts/testflight.sh` does bump → archive → export → upload. Credentials live in `scripts/.env` (gitignored). Two auth modes supported: App Store Connect API key (preferred) or Apple ID + app-specific password. Latest uploaded build is in the project's `CURRENT_PROJECT_VERSION`.

## ROADMAP

The living roadmap is `ROADMAP.md` at the project root. It's edited freely as work progresses — keep it accurate. Phases 1–6 have shipped; remaining work is documented as `[ ]` items plus a "Deferred" section for things blocked on external resources (paid Apple dev account, AI assets, audio, telemetry backend).
