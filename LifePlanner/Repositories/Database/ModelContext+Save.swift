import SwiftData

extension ModelContext {
    /// Persist pending mutations, swallowing the error. SwiftData's autosave is
    /// timing-sensitive: an app kill or rapid context teardown after `insert`
    /// can lose the row, so user-facing mutations call this explicitly.
    func saveQuietly() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
