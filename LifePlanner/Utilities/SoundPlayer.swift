import Foundation
import AVFoundation

/// Named one-shot sound effects + the looping farm ambience. The player tries
/// to load a matching audio file from the main bundle (`.caf`, `.mp3`, `.wav`
/// in that order). When no file is found — which is the case today, since
/// Phase 2's audio pack isn't shipped yet — `play(_:)` and `startAmbience()`
/// silently no-op. That keeps every call site wired so dropping a single audio
/// asset into the bundle later starts producing sound with no code change.
///
/// Lives in Utilities (not under UI) so both interactors and views can call
/// it without a layering violation. Treated as a fire-and-forget singleton —
/// games typically don't DI-inject SFX, and the no-op fallback means tests
/// can ignore it.
@MainActor
final class SoundPlayer {

    static let shared = SoundPlayer()

    enum Effect: String, CaseIterable {
        case contribution = "sfx_contribution"
        case questClaim   = "sfx_quest_claim"
        case questReroll  = "sfx_quest_reroll"
        case purchase     = "sfx_purchase"
    }

    private static let ambienceResource = "sfx_farm_ambience"

    private var effects: [Effect: AVAudioPlayer] = [:]
    private var ambience: AVAudioPlayer?
    private var sessionConfigured = false

    private init() {}

    // MARK: - One-shot effects

    /// Play a short effect. Volume defaults low so multiple overlapping plays
    /// don't fatigue the ear. Silent if the bundle has no matching file.
    func play(_ effect: Effect, volume: Float = 0.4) {
        configureSessionIfNeeded()
        guard let player = loadEffect(effect) else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func loadEffect(_ effect: Effect) -> AVAudioPlayer? {
        if let cached = effects[effect] { return cached }
        guard let player = makePlayer(named: effect.rawValue) else { return nil }
        player.prepareToPlay()
        effects[effect] = player
        return player
    }

    // MARK: - Looping ambience

    /// Start the farm ambience loop. Idempotent; already-playing is a no-op.
    /// Silent if the bundle has no matching file.
    func startAmbience(volume: Float = 0.15) {
        configureSessionIfNeeded()
        if ambience == nil {
            ambience = makePlayer(named: Self.ambienceResource)
            ambience?.numberOfLoops = -1
            ambience?.prepareToPlay()
        }
        guard let player = ambience, !player.isPlaying else { return }
        player.volume = volume
        player.play()
    }

    func stopAmbience() {
        ambience?.stop()
    }

    // MARK: - Helpers

    private func makePlayer(named base: String) -> AVAudioPlayer? {
        for ext in ["caf", "mp3", "wav", "m4a"] {
            if let url = Bundle.main.url(forResource: base, withExtension: ext),
               let player = try? AVAudioPlayer(contentsOf: url) {
                return player
            }
        }
        return nil
    }

    /// Use the `ambient` category so playback mixes with the user's music and
    /// respects the silent switch — game SFX shouldn't interrupt podcasts or
    /// override Do Not Disturb expectations.
    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
