# LifePlanner Roadmap

Living doc — Phase 5 polish + concrete follow-ups from sim verification.
Edit freely; commits welcome.

## Phase 5 — Polish

Items we deferred from Phase 2 plus broader polish. Ordered roughly by user-visible
impact, not by sequence — pick whatever's most useful next.

- [ ] **Notification scheduling for Tasks.** Habits ✅ (see follow-ups
      below). Tasks `dueDate` still isn't wired to `UNUserNotificationCenter`
      — apply the same pattern (`NotificationScheduler.scheduleTaskDue` +
      cancel on complete/delete).
- [ ] **iCloud sync.** Schema is already CloudKit-compatible (no `.unique`,
      defaults everywhere, optional to-many relationships). Flip the entitlement
      and use `ModelConfiguration(cloudKitDatabase:)`. Requires a paid Apple
      Developer account.
- [ ] **Habit polish.** Weekly + custom cadence (`HabitFrequency` enum is already
      extensible without schema migration), streak calculation, target-count
      per period.
- [ ] **Today summary.** Cross-feature dashboard: tasks due today + habits to
      log + active goals at a glance. Display as the Tasks tab header.

### Tasks
- [ ] **Sort toggle.** Allow user to switch sort order between *due date* (current
      default) and *priority*. Surface as a toolbar menu or a segmented control
      above the list. Persist the choice in `AppState` so it survives navigation;
      maybe persist to `UserDefaults` longer-term.

### Habits
- [x] **Make edit discoverable.** ✅ Tap the title area opens the edit sheet
      (chevron affordance); tap the leading circle still toggles done. Swipe
      trailing remains archive/delete. (Commit referenced from this entry.)
- [x] **Reminder = real push notification.** ✅ `RealNotificationScheduler`
      wraps `UNUserNotificationCenter`; `RealHabitsInteractor` schedules /
      cancels on add / update / archive / delete using a stable
      `habit-reminder-<UUID>` identifier. Permission is requested on first
      schedule. Footer text in `AddHabitSheet` updated.

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
- swipe right to mark as contacted
- pin up to 9 contacts as favorites, similar to iMessage (stay on top, bigger avatars)
- sync avatar from contacts
- set reminder — contact reminder to call or reach out to friends / family
    - suggest a text prompt
    - open an iOS sharing modal that allows email/text/phone call etc


## TestFlight setup

### Per-build flow

Once prerequisites are done, every TestFlight upload goes:

1. **Bump build number** in the project (`CURRENT_PROJECT_VERSION`).
   TestFlight rejects duplicate `(CFBundleShortVersionString, CFBundleVersion)`
   pairs, so increment for every upload — even if the marketing version
   (`MARKETING_VERSION`) doesn't change. A small script can `agvtool next-version
   -all` for you.
2. **Archive** with a Release configuration:
   ```
   xcodebuild -project LifePlanner.xcodeproj \
     -scheme LifePlanner \
     -destination 'generic/platform=iOS' \
     -configuration Release \
     -archivePath build/LifePlanner.xcarchive \
     archive
   ```
3. **Export the IPA** for App Store distribution. Needs an
   `ExportOptions.plist` file (commit it under `scripts/`):
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>method</key><string>app-store-connect</string>
     <key>teamID</key><string>YOUR_TEAM_ID</string>
     <key>signingStyle</key><string>automatic</string>
     <key>uploadBitcode</key><false/>
     <key>uploadSymbols</key><true/>
   </dict></plist>
   ```
   Then:
   ```
   xcodebuild -exportArchive \
     -archivePath build/LifePlanner.xcarchive \
     -exportPath build/export \
     -exportOptionsPlist scripts/ExportOptions.plist
   ```
4. **Upload** via `xcrun altool` (the simplest path). With an app-specific
   password:
   ```
   xcrun altool --upload-app \
     --type ios \
     --file build/export/LifePlanner.ipa \
     --username APPLE_ID_EMAIL \
     --password APP_SPECIFIC_PASSWORD
   ```
   Or with an API key (preferred — survives password rotations):
   ```
   xcrun altool --upload-app \
     --type ios \
     --file build/export/LifePlanner.ipa \
     --apiKey KEY_ID \
     --apiIssuer ISSUER_ID
   ```
   Apple's preferred newer path is `xcrun notarytool` for notarization +
   `xcrun altool --upload-app` for App Store Connect. For TestFlight only,
   `altool` alone is fine.
5. **Wait for processing.** After upload, App Store Connect runs build
   processing for ~5–30 min. Once done, the build appears under
   TestFlight → iOS Builds.
6. **Add testers.** TestFlight → Internal Testing → "+" → add yourself
   (or a group). Internal testers are anyone on your team with App Store
   Connect access — up to 100, instant, no review. External testers (up
   to 10,000) require a one-time Beta App Review for the first build of
   each marketing version.
7. **Install on your phone.** Tester gets an email + push from the
   TestFlight app → tap to install.

### To automate (after first manual run works)

Wrap steps 1–4 in `scripts/testflight.sh`. Suggested:
- Read `TEAM_ID`, `APPLE_ID`, `APP_SPECIFIC_PASSWORD` (or API key triple)
  from a `.env` file (gitignored).
- Run `agvtool next-version -all`.
- Archive → export → upload.
- Echo "Build N uploaded — processing in App Store Connect."

### Known gotchas

- **Capabilities you'll add later that need to land BEFORE the first
  archive** if possible (avoids profile re-issuance churn): App Group
  entitlement (for Widgets), Push Notifications (for habit reminders),
  iCloud (for SwiftData CloudKit). Adding them later forces a new
  provisioning profile, which automatic signing handles but adds a delay.
- **Match version with what's in App Store Connect.** If you change
  `MARKETING_VERSION` from 1.0 → 1.1, the next external testing pass
  needs another Beta App Review.
- **`altool` is being phased out for upload eventually**, but as of Xcode
  16 it still works. If/when Apple removes it, switch to Transporter or
  the App Store Connect API directly.
