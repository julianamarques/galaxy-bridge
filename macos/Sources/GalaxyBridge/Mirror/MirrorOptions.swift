import Foundation
import GalaxyKit

struct MirrorOptions {
    enum Key {
        static let quality = "mirrorQuality"
        static let audio = "mirrorAudio"
        static let turnScreenOff = "mirrorTurnScreenOff"
        static let alwaysOnTop = "mirrorAlwaysOnTop"
    }

    var quality: Quality
    var codec = Codec.h264
    var audio: Bool
    var turnScreenOff: Bool
    var stayAwake = true
    var alwaysOnTop: Bool

    init(defaults: UserDefaults = .standard) {
        quality = defaults.string(forKey: Key.quality).flatMap(Quality.init(rawValue:)) ?? .high
        audio = defaults.object(forKey: Key.audio) as? Bool ?? true
        turnScreenOff = defaults.bool(forKey: Key.turnScreenOff)
        alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
    }

    var serverArguments: [String] {
        var args = [
            "log_level=info",
            "tunnel_forward=true",
            "video_codec=\(codec.rawValue)",
            "video_bit_rate=\(quality.bitRate)",
            audio ? "audio_codec=raw" : "audio=false",
        ]
        if let size = quality.maxSize { args.append("max_size=\(size)") }
        if stayAwake { args.append("stay_awake=true") }
        return args
    }
}
