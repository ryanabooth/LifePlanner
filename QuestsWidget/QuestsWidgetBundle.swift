import WidgetKit
import SwiftUI

/// Entry point for the LifePlanner widget extension.
///
/// ## Xcode setup (one-time)
/// 1. File → New → Target → Widget Extension.  Name it "QuestsWidget".
/// 2. Drag all files from the `QuestsWidget/` folder into the new target (do NOT
///    also add them to the main LifePlanner target).
/// 3. Enable App Groups on BOTH targets, using the same group ID
///    (e.g. `group.com.lifeplanner.shared`).
/// 4. Update `ModelContainer.appModelContainer()` to use the shared group URL
///    instead of the default Documents directory so both targets read the same store.
@main
struct QuestsWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuestsWidget()
    }
}

struct QuestsWidget: Widget {
    let kind = "QuestsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuestProvider()) { entry in
            QuestsWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Quests")
        .description("See your daily quest progress and gold balance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
