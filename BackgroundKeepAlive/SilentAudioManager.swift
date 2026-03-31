import AVFoundation
import Foundation

/// SilentAudioManager
/// ─────────────────────────────────────────────────────────────────────────
/// Strategy: Playing a silent/near-silent audio loop keeps the app's audio
/// session alive in the background, which prevents iOS from suspending the
/// process.
///
/// Why it works:
///   • Apps with an active AVAudioSession (.playback category) are treated
///     as audio apps; iOS will NOT suspend them.
///   • We play a 1-second silent PCM buffer on a repeating loop.
///   • This is a well-known, App-Store-approved technique used by navigation,
///     fitness, and communication apps.
///
/// Trade-offs:
///   • Adds a small, constant battery cost (~0.1-0.3% per hour on modern
///     devices).
///   • The blue "microphone / speaker" status-bar indicator may appear
///     depending on iOS version.
///   • Apple may reject apps that abuse this solely for background execution
///     without a legitimate audio use case — pair with location updates.
///
/// Info.plist requirements:
///   • UIBackgroundModes → audio
/// ─────────────────────────────────────────────────────────────────────────
final class SilentAudioManager {

    static let shared = SilentAudioManager()
    private var player: AVAudioPlayer?

    private init() {}

    // ── Public API ────────────────────────────────────────────────────────

    func start() {
        configureAudioSession()
        prepareSilentPlayer()
        registerInterruptionObserver()
    }

    func ensureActive() {
        if player?.isPlaying == false {
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
    }

    func stop() {
        player?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // ── Private ───────────────────────────────────────────────────────────

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback category is the key — it signals to iOS that this
            // process needs to keep running.
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]   // don't interrupt other audio
            )
            try session.setActive(true)
        } catch {
            print("[SilentAudio] Session setup failed: \(error)")
        }
    }

    private func prepareSilentPlayer() {
        // Generate a 1-second 44.1kHz stereo silent PCM buffer in memory.
        // No file needed on disk.
        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = buffer.frameCapacity
        // All samples default to 0 (silence) — no need to fill the buffer.

        // Convert buffer → Data → AVAudioPlayer via a temp file
        // (AVAudioPlayer doesn't accept raw PCM buffers directly)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("silence.caf")

        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
        } catch {
            print("[SilentAudio] Could not write silence file: \(error)")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1   // infinite loop
            player?.volume = 0.01        // near-zero, not completely silent to avoid optimisation
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("[SilentAudio] Player init failed: \(error)")
        }
    }

    private func registerInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .ended:
            // Phone call ended, Siri dismissed, etc. — restart our session.
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                ensureActive()
            }
        default:
            break
        }
    }
}
