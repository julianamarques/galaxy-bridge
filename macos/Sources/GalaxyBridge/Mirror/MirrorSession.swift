import AppKit
import AVFoundation
import GalaxyKit

@MainActor
protocol MirrorTransport: AnyObject {
    var codec: Codec { get }
    var lastError: String? { get }
    var requestKeyFrame: @Sendable () -> Void { get }
    func start(_ feed: VideoFeed)
    func send(_ message: ControlMessage)
    func close()
}

final class VideoFeed: @unchecked Sendable {
    enum Event: Sendable {
        case videoSize(CGSize)
        case firstFrame
        case clipboard(String)
        case ended(String)
    }

    let deliver: @Sendable (Event) -> Void
    private let builder: VideoSampleBuilder
    private let renderer: VideoRenderer

    init(codec: Codec, renderer: VideoRenderer, deliver: @escaping @Sendable (Event) -> Void) {
        builder = VideoSampleBuilder(codec: codec)
        self.renderer = renderer
        self.deliver = deliver
    }

    func session(width: Int, height: Int) {
        renderer.flush()
        deliver(.videoSize(CGSize(width: width, height: height)))
    }

    func config(_ payload: [UInt8]) throws {
        try builder.applyConfig(payload)
    }

    func frame(_ payload: [UInt8], pts: UInt64, isKeyFrame: Bool) throws {
        if let sample = try builder.sampleBuffer(payload, pts: pts, isKeyFrame: isKeyFrame),
           renderer.enqueue(sample, isKeyFrame: isKeyFrame) {
            deliver(.firstFrame)
        }
    }
}

@MainActor
final class MirrorSession {
    let displayLayer = AVSampleBufferDisplayLayer()
    private(set) var videoSize: CGSize = .zero
    var onVideoSizeChange: ((CGSize) -> Void)?

    private let transport: MirrorTransport
    private var hasFrame = false
    private var endMessage: String?
    private var isStopped = false
    private var firstFrameWaiter: CheckedContinuation<Void, Error>?
    private var endWaiter: CheckedContinuation<String?, Never>?
    private var lastClipboard: String?
    private var clipboardSequence: UInt64 = 0

    init(transport: MirrorTransport) {
        self.transport = transport
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
    }

    func start() {
        let deliver: @Sendable (VideoFeed.Event) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        let renderer = VideoRenderer(renderer: displayLayer.sampleBufferRenderer, requestKeyFrame: transport.requestKeyFrame)
        transport.start(VideoFeed(codec: transport.codec, renderer: renderer, deliver: deliver))
    }

    func waitForFirstFrame(timeout: TimeInterval) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if hasFrame { return continuation.resume() }
                if let endMessage { return continuation.resume(throwing: ToolError.failed(endMessage)) }
                if isStopped { return continuation.resume(throwing: CancellationError()) }
                firstFrameWaiter = continuation
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    MainActor.assumeIsolated { self?.resumeFirstFrameWaiter(throwing: ToolError.mirrorTimeout) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func waitUntilEnded() async -> String? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                if isStopped { return continuation.resume(returning: endMessage) }
                endWaiter = continuation
            }
        } onCancel: {
            Task { @MainActor in self.stop() }
        }
    }

    func send(_ message: ControlMessage) {
        guard !isStopped else { return }
        transport.send(message)
    }

    func sendKey(_ keycode: AndroidKeycode) {
        send(.keycode(action: .down, keycode: keycode.rawValue))
        send(.keycode(action: .up, keycode: keycode.rawValue))
    }

    func paste(_ text: String) {
        clipboardSequence += 1
        lastClipboard = text
        send(.setClipboard(sequence: clipboardSequence, text: text, paste: true))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        transport.close()
        resumeFirstFrameWaiter(throwing: endMessage.map { ToolError.failed($0) } ?? CancellationError())
        endWaiter?.resume(returning: endMessage)
        endWaiter = nil
    }

    private func resumeFirstFrameWaiter(throwing error: Error) {
        firstFrameWaiter?.resume(throwing: error)
        firstFrameWaiter = nil
    }

    private func handle(_ event: VideoFeed.Event) {
        guard !isStopped else { return }
        switch event {
        case .videoSize(let size):
            videoSize = size
            onVideoSizeChange?(size)
        case .firstFrame:
            hasFrame = true
            firstFrameWaiter?.resume()
            firstFrameWaiter = nil
        case .clipboard(let text):
            guard text != lastClipboard else { return }
            lastClipboard = text
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .ended(let message):
            endMessage = transport.lastError ?? message
            stop()
        }
    }
}
