import AVFoundation
import Foundation

/// Voice alert settings, stored in UserDefaults (read by @AppStorage in views).
enum VoiceSettings {
    static let enabledKey = "voice.enabled"
    static let languageKey = "voice.language"
    static let targetKey = "voice.target"
    static let stopKey = "voice.stop"
    static let entryKey = "voice.entry"
    static let buyKey = "voice.buy"
    static let sellKey = "voice.sell"
    static let signalsKey = "voice.signals"
    static let detailsKey = "voice.details"
    static let backgroundKey = "voice.background"
    static let keepAwakeKey = "voice.keepAwake"

    static let defaultTarget = "Target fill"
    static let defaultStop = "Stop loss fill"
    static let defaultEntry = "Order filled"
    static let defaultBuy = "Buy signal"
    static let defaultSell = "Sell signal"

    private static var defaults: UserDefaults { .standard }

    static var enabled: Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }
    static var language: String { defaults.string(forKey: languageKey) ?? "en-US" }
    static var speakSignals: Bool { defaults.object(forKey: signalsKey) as? Bool ?? true }
    /// Add the symbol, price and profit after the phrase.
    static var speakDetails: Bool { defaults.object(forKey: detailsKey) as? Bool ?? false }
    static var runInBackground: Bool { defaults.object(forKey: backgroundKey) as? Bool ?? false }

    static func phrase(_ key: String, default value: String) -> String {
        let text = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? value : text
    }
}

/// Speaks alerts out loud, also over other audio and with the screen locked
/// when background listening is on.
@MainActor
final class VoiceAnnouncer {
    static let shared = VoiceAnnouncer()

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, force: Bool = false) {
        guard force || VoiceSettings.enabled, !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: VoiceSettings.language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1
        synthesizer.speak(utterance)
    }
}

/// Keeps the app running with the screen locked by playing silence, so the
/// live feed, the demo account and the voice alerts keep working.
/// Uses more battery; turned on in the voice alert settings.
@MainActor
final class BackgroundAudio {
    static let shared = BackgroundAudio()

    private var player: AVAudioPlayer?

    var isRunning: Bool { player?.isPlaying == true }

    func start() {
        guard player == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        guard let player = try? AVAudioPlayer(data: Self.silence(seconds: 2)) else { return }
        player.numberOfLoops = -1
        player.volume = 0.01
        player.play()
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }

    /// A mono 16-bit PCM WAV file of silence.
    static func silence(seconds: Double, sampleRate: Int = 8000) -> Data {
        let samples = Int(seconds * Double(sampleRate))
        let dataSize = samples * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))                      // PCM
        append(UInt16(1))                      // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))         // byte rate
        append(UInt16(2))                      // block align
        append(UInt16(16))                     // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
