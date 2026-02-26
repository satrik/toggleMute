// Plays a short audio cue on mute/unmute using AppKit's NSSound — zero extra frameworks.

import Cocoa

final class SoundFeedbackManager {

    static let shared = SoundFeedbackManager()
    private var preferences = Preferences()

    // Pre-load both sounds once so playback is instant.
    private let muteSound: NSSound? = {
        if let s = NSSound(named: NSSound.Name("Tink")) {
            s.volume = 0.6
            return s
        }
        return nil
    }()

    private let unmuteSound: NSSound? = {
        if let s = NSSound(named: NSSound.Name("Pop")) {
            s.volume = 0.6
            return s
        }
        return nil
    }()

    private init() {}

    func playMute() {
        guard preferences.muteSoundEnabled else { return }
        // Stop any previous playback first so rapid toggling doesn't queue up sounds
        muteSound?.stop()
        muteSound?.play()
    }

    func playUnmute() {
        guard preferences.muteSoundEnabled else { return }
        unmuteSound?.stop()
        unmuteSound?.play()
    }
}
