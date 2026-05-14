# Tiller

A native iOS productivity farming sim built in SwiftUI + SwiftData + SpriteKit. Habits, tasks, and goals drive growth on a 2D farm; daily quests pay gold.

Bootstrapped from the
[clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui)
template by Alexey Naumov (MIT). See [NOTICE.md](NOTICE.md).

## Status

Phases 1–6 shipped (TestFlight). Phase 7 (polish & retention) in progress.

## Requirements

- Xcode 16+
- iOS 18+ deployment target
- Swift 5.9+

## Architecture

```
View (@Query reads)     ← SwiftUI, reactive against SwiftData rows
   ↓
Interactor (mutations)  ← business logic; only layer that writes
   ↓
ModelContext            ← SwiftData; saveQuietly() after every mutation
```

Interactors are injected via `@Environment(\.injected)` (`DIContainer`). Real implementations in `AppEnvironment.bootstrap`; no-op `Stub*` versions for previews and tests.

## Features

- **Tasks** — create, edit, prioritise, tag, set due dates, recurring schedules (daily / weekdays / weekly / monthly / yearly)
- **Habits** — daily and weekly cadence, streak tracking with milestone bonuses, reminder notifications
- **Goals** — each goal binds a farm plot; sub-goals supported
- **Farm** — SpriteKit 2D scene; plot health driven by habit/task completions; decay over time; cosmetic shop (hats, outfits, pets, farmhouse decor)
- **Quests** — three daily quests + one weekly harvest quest; auto-claimed on completion; gold rewards; re-roll for a cost
- **Gold economy** — earned from quests and streak milestones; spent on plot capacity upgrades and cosmetics
- **Widget** — today's quests in a WidgetKit extension (small/medium)
- **Siri / Shortcuts** — open farm, roll quests, log a habit
- **Spotlight** — open tasks indexed for system search
- **Notifications** — task due reminders, habit reminders, streak milestones

## Building

```bash
xcodebuild -scheme LifePlanner \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -configuration Debug build test
```

## TestFlight

```bash
scripts/testflight.sh
```

Credentials live in `scripts/.env` (gitignored). See the script header for the required env vars.
