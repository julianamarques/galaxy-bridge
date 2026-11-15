import Foundation
import GalaxyKit

@MainActor
final class ScrcpyTransport: MirrorTransport {
    let codec: Codec
    let requestKeyFrame: @Sendable () -> Void
    private let connection: ServerConnection
    private let controlQueue: DispatchQueue
    private var audioPlayer: AudioPlayer?

    init(connection: ServerConnection, codec: Codec) {
        self.connection = connection
        self.codec = codec
        let queue = DispatchQueue(label: "GalaxyBridge.mirror.control")
        controlQueue = queue
        let control = connection.control
        requestKeyFrame = { queue.async { try? control.write(ControlMessage.resetVideo.data) } }
    }

    var lastError: String? { connection.log.lastError }

    func start(_ feed: VideoFeed) {
        let video = connection.video
        Thread.detachNewThread { Self.readVideo(from: video, feed: feed) }
        if let audio = connection.audio {
            let player = AudioPlayer()
            if (try? player.start()) != nil {
                audioPlayer = player
                Thread.detachNewThread { try? Self.readAudio(from: audio, player: player) }
            }
        }
        let control = connection.control
        Thread.detachNewThread { Self.readDeviceMessages(from: control, feed: feed) }
    }

    func send(_ message: ControlMessage) {
        let control = connection.control
        let data = message.data
        controlQueue.async { try? control.write(data) }
    }

    func close() {
        audioPlayer?.stop()
        connection.close()
    }

    private nonisolated static func readVideo(from socket: TCPSocket, feed: VideoFeed) {
        do {
            guard Codec(scrcpyID: try socket.read(exactly: 4).bigEndian(at: 0)) != nil else {
                throw ToolError.failed(String(localized: "O Galaxy não conseguiu iniciar o vídeo."))
            }
            while true {
                guard let header = ScrcpyProtocol.parseHeader(try socket.read(exactly: ScrcpyProtocol.headerLength)) else {
                    throw ToolError.failed(String(localized: "Dados de vídeo inválidos."))
                }
                switch header {
                case let .session(width, height):
                    feed.session(width: width, height: height)
                case let .media(isConfig, isKeyFrame, pts, size):
                    let payload = try socket.read(exactly: size)
                    if isConfig {
                        try feed.config(payload)
                    } else {
                        try feed.frame(payload, pts: pts, isKeyFrame: isKeyFrame)
                    }
                }
            }
        } catch {
            feed.deliver(.ended(error.localizedDescription))
        }
    }

    private nonisolated static func readAudio(from socket: TCPSocket, player: AudioPlayer) throws {
        guard try socket.read(exactly: 4).bigEndian(at: 0, as: UInt32.self) == ScrcpyProtocol.rawAudioCodecID else { return }
        while case let .media(isConfig, _, _, size)? = ScrcpyProtocol.parseHeader(try socket.read(exactly: ScrcpyProtocol.headerLength)) {
            let payload = try socket.read(exactly: size)
            if !isConfig { player.play(interleavedInt16: payload) }
        }
    }

    private nonisolated static func readDeviceMessages(from socket: TCPSocket, feed: VideoFeed) {
        while let message = try? DeviceMessage.read(using: socket.read(exactly:)) {
            if case .clipboard(let text) = message {
                feed.deliver(.clipboard(text))
            }
        }
    }
}
