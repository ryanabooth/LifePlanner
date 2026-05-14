# Tiller

A native iOS personal organizer (tasks, contacts, goals, habits) built in
SwiftUI with the Observation framework and SwiftData.

Bootstrapped from the
[clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui)
template by Alexey Naumov (MIT). See [NOTICE.md](NOTICE.md).

## Status

Project skeleton — features not yet implemented.

## Requirements

- Xcode 15+
- iOS 17+ deployment target
- Swift 5.9+

## Architecture

View → Interactor → Repository → SwiftData / system framework.
`AppState` is the shared `@Observable` store, injected via `DIContainer`.

## Roadmap

1. Tasks
2. Habits
3. Goals (cross-references Tasks and Habits)
4. Contacts (syncs with the system address book)
5. iCloud sync, widgets, App Intents
