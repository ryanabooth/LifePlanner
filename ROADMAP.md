# LifePlanner Roadmap

Living doc — Phase 5 polish + concrete follow-ups from sim verification.
Edit freely; commits welcome.

## Phase 5 — Polish

Items we deferred from Phase 2 plus broader polish. Ordered roughly by user-visible
impact, not by sequence — pick whatever's most useful next.

- [ ] **Notification scheduling.** Tasks (`dueDate`) and Habits (`reminderTime`)
      both store the data but nothing's wired to `UNUserNotificationCenter`. See
      "Habits → reminder = push notification" follow-up below; Tasks needs the
      same treatment for due-date alerts.
- [ ] **iCloud sync.** Schema is already CloudKit-compatible (no `.unique`,
      defaults everywhere, optional to-many relationships). Flip the entitlement
      and use `ModelConfiguration(cloudKitDatabase:)`. Requires a paid Apple
      Developer account.
- [ ] **Habit polish.** Weekly + custom cadence (`HabitFrequency` enum is already
      extensible without schema migration), streak calculation, target-count
      per period.
- [ ] **Goal polish.** Sub-goals (parent/child hierarchy on `DBModel.Goal`),
      metric tracking ("12/24 books read") with units.
- [ ] **Today summary.** Cross-feature dashboard: tasks due today + habits to
      log + active goals at a glance. Could be a 5th tab or the Tasks tab header.
- [ ] **WidgetKit extension.** Tasks-due-today and Habit-streak widgets. Stub
      the App Group entitlement now if widgets are likely (avoids a store
      migration later).
- [ ] **App Intents / Shortcuts.** "Add task to LifePlanner", "Mark habit done",
      "Log interaction with [contact]".
- [ ] **Spotlight indexing.** Tasks and contacts searchable from system search.
- [ ] **Goal ↔ Contact linking** (deferred — owner mentioned a future social
      app would be the better home for this).

## Follow-ups from sim verification (2026-05-07)

### Tasks
- [ ] **Sort toggle.** Allow user to switch sort order between *due date* (current
      default) and *priority*. Surface as a toolbar menu or a segmented control
      above the list. Persist the choice in `AppState` so it survives navigation;
      maybe persist to `UserDefaults` longer-term.

### Habits
- [ ] **Make edit discoverable.** Edit currently sits behind a swipe-leading
      action (blue pencil); the owner couldn't find it. Tasks uses tap-to-edit
      with swipe for toggle/delete — Habits should match that pattern for
      consistency. Proposal: tap → edit sheet; swipe leading → toggle done;
      swipe trailing → archive/delete.
- [ ] **Reminder = real push notification.** Today, `Habit.reminderTime` is
      stored but not scheduled. Wire up `UNUserNotificationCenter`:
      - On habit save, schedule a daily local notification at `reminderTime`
        (or remove if reminder cleared).
      - On habit delete, cancel the notification.
      - Use a stable identifier per habit (`"habit-\(habit.id.uuidString)"`)
        so updates replace cleanly.
      - Need notification permission flow; `UserPermissionsInteractor` already
        has `.notifications` plumbing — call `request(permission:)` first time
        the user enables a reminder.
      - Remove the current "saved but not scheduled yet" footer from
        `AddHabitSheet`.

### Contacts
- [ ] **Swipe-right to mark interaction.** Add a leading swipe action on the
      contacts list row that records `lastInteraction = now` for that contact.
      Faster than tap → detail → "Mark interaction now."
- [ ] **Sort by most-recent interaction by default.** Today the list uses iOS
      Contacts' `userDefault` sort order (alphabetical). Change default sort to:
      contacts with a `lastInteraction` date first (most-recent first), then
      everyone else alphabetically. Add a sort-mode toggle (recent / alpha).
      Implementation note: `lastInteraction` lives in our `DBModel.Contact`
      enrichment, so the sort needs to merge the system contact list with the
      enrichment table — fetch enrichments into a `[String: Date]` keyed by
      `systemIdentifier` once, then sort the system list with that lookup.

## TestFlight setup

Goal: get the app onto the owner's iPhone via TestFlight so it can be
exercised end-to-end on a real device.

**Prerequisites (one-time):**
- [ ] Apple Developer Program enrollment ($99/year). Without this, code signing
      for App Store / TestFlight distribution isn't possible.
- [ ] Team set in Xcode project (`DEVELOPMENT_TEAM` build setting). Currently
      empty — Xcode auto-fills once a team is selected in Signing & Capabilities.
- [ ] Bundle ID `com.rbooth.lifeplanner` registered with the team (App Store
      Connect → Identifiers, or auto-registered on first archive).
- [ ] App record in App Store Connect (name, bundle ID, primary language).

**Per-build flow:**
1. Bump build number (`CURRENT_PROJECT_VERSION`) — TestFlight rejects duplicate builds.
2. `xcodebuild archive` with `-archivePath` and a Release configuration.
3. `xcodebuild -exportArchive` with an `ExportOptions.plist` for App Store.
4. Upload via `xcrun altool --upload-app` (or Transporter app, or Xcode Organizer).
5. In App Store Connect → TestFlight: add the build to a test group; add
   testers (internal = up to 100 people on your team, instant; external =
   up to 10,000 with a one-time review).

A self-contained build/upload script (`scripts/testflight.sh`) is worth creating
once the prerequisites are settled.
