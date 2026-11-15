import BridgeProtocol
import Foundation
import GalaxyKit

@MainActor
final class AppTransport: MirrorTransport {
    private enum Kind: UInt8 {
        case session = 0
        case config = 1
        case frame = 2
        case keyFrame = 3
        case audio = 4
    }

    private static let headerLength = 9

    let codec = Codec.h264
    private(set) var lastError: String?
    private let sendMessage: (Message) -> Void
    private let stopStream: () -> Void
    private var feed: VideoFeed?
    private var audioPlayer: AudioPlayer?
    private var audioFailed = false
    private var isClosed = false

    init(send: @escaping (Message) -> Void, stopStream: @escaping () -> Void) {
        sendMessage = send
        self.stopStream = stopStream
    }

    var requestKeyFrame: @Sendable () -> Void {
        { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.sendMessage(.mirrorSync) } }
        }
    }

    func start(_ feed: VideoFeed) {
        self.feed = feed
    }

    func begin(_ start: MirrorStart) {
        sendMessage(.mirrorStart(start))
    }

    func received(_ body: Data) {
        guard let feed, body.count >= Self.headerLength, let kind = Kind(rawValue: body[body.startIndex]) else { return }
        let bytes = [UInt8](body)
        let pts = bytes[1..<Self.headerLength].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let payload = Array(bytes[Self.headerLength...])
        do {
            switch kind {
            case .session:
                guard payload.count >= 8 else { return }
                feed.session(width: Int(payload.bigEndian(at: 0, as: UInt32.self)), height: Int(payload.bigEndian(at: 4, as: UInt32.self)))
            case .config:
                try feed.config(payload)
            case .frame, .keyFrame:
                try feed.frame(payload, pts: pts, isKeyFrame: kind == .keyFrame)
            case .audio:
                play(payload)
            }
        } catch {
            end(error.localizedDescription)
        }
    }

    private func play(_ samples: [UInt8]) {
        if audioPlayer == nil, !audioFailed {
            let player = AudioPlayer()
            if (try? player.start()) != nil { audioPlayer = player } else { audioFailed = true }
        }
        audioPlayer?.play(interleavedInt16: samples)
    }

    func stateChanged(_ state: MirrorState) {
        guard state.state == .stopped else { return }
        lastError = state.message
        end(state.message ?? String(localized: "O espelhamento foi encerrado no Galaxy."))
    }

    func streamEnded() {
        end(String(localized: "A conexão com o Galaxy caiu."))
    }

    func send(_ message: ControlMessage) {
        switch message {
        case let .touch(action, _, position, _, _, _):
            let touch: MirrorTouch.Action = switch action {
            case .down: .down
            case .move: .move
            case .up: .up
            }
            sendMessage(.mirrorTouch(MirrorTouch(
                action: touch, x: Int(position.x), y: Int(position.y),
                width: Int(position.screenWidth), height: Int(position.screenHeight)
            )))
        case let .scroll(position, horizontal, vertical, _):
            sendMessage(.mirrorScroll(MirrorScroll(
                x: Int(position.x), y: Int(position.y),
                width: Int(position.screenWidth), height: Int(position.screenHeight),
                dx: Double(horizontal), dy: Double(vertical)
            )))
        case .backOrScreenOn(.down):
            sendMessage(.mirrorKey(MirrorKey(key: .back)))
        case let .keycode(.down, keycode, _, _):
            if let key = Self.key(for: keycode) { sendMessage(.mirrorKey(MirrorKey(key: key))) }
        case let .text(text), let .setClipboard(_, text, true):
            sendMessage(.mirrorText(MirrorText(text: text)))
        case let .setClipboard(_, text, false):
            sendMessage(.clipboard(Clipboard(text: String(text.prefix(Clipboard.maxLength)))))
        case let .getClipboard(cut):
            sendMessage(.mirrorKey(MirrorKey(key: cut ? .cut : .copy)))
        case .resetVideo:
            requestKeyFrame()
        default:
            break
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        audioPlayer?.stop()
        audioPlayer = nil
        sendMessage(.mirrorStop)
        stopStream()
    }

    private func end(_ message: String) {
        feed?.deliver(.ended(message))
    }

    private static func key(for keycode: Int32) -> MirrorKey.Key? {
        switch AndroidKeycode(rawValue: keycode) {
        case .home: .home
        case .back, .escape: .back
        case .appSwitch: .recents
        case .enter: .enter
        case .delete: .delete
        default: nil
        }
    }
}
