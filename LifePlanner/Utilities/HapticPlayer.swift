import UIKit

/// Haptic counterpart to `SoundPlayer`. Fires tactile feedback alongside audio
/// so users on silent still feel interactions. The `.ambient` audio session
/// category already silences sounds when the mute switch is on — pairing
/// haptics here means no additional silent-switch detection is needed.
///
/// Treated as a fire-and-forget singleton, same as SoundPlayer.
@MainActor
final class HapticPlayer {

    static let shared = HapticPlayer()
    private init() { prepare() }

    private let softGen   = UIImpactFeedbackGenerator(style: .soft)
    private let lightGen  = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen  = UIImpactFeedbackGenerator(style: .rigid)
    private let notifGen  = UINotificationFeedbackGenerator()

    private func prepare() {
        softGen.prepare()
        lightGen.prepare()
        mediumGen.prepare()
        rigidGen.prepare()
        notifGen.prepare()
    }

    /// Short soft tap — for button presses and minor UI interactions.
    func tap() {
        softGen.impactOccurred()
    }

    /// Three-beat ascending pattern: light → medium → rigid.
    /// Use when completing a task or logging a habit.
    func crescendo() {
        lightGen.impactOccurred(intensity: 0.4)
        Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(100))
            mediumGen.impactOccurred(intensity: 0.7)
            try? await Task.sleep(for: .milliseconds(120))
            rigidGen.impactOccurred(intensity: 1.0)
        }
    }

    /// Notification-style success pulse — for purchases and quest claims.
    func success() {
        notifGen.notificationOccurred(.success)
    }
}
