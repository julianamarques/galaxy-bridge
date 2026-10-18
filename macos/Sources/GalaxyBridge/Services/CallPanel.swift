import AppKit
import BridgeProtocol
import Combine
import SwiftUI

@MainActor
final class CallPanel {
    private let app: AppModel
    private var panel: NSPanel?
    private var hiddenCall: String?
    private var isShowing = false
    private var subscription: AnyCancellable?

    init(app: AppModel) {
        self.app = app
        subscription = app.$call
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in self?.update(call) }
    }

    private func update(_ call: CallState?) {
        guard let call, call.call != hiddenCall, call.state != .voicemail else { return hide() }
        show()
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        isShowing = true
        if !panel.isVisible || panel.alphaValue == 0 {
            position(panel)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, isShowing else { return }
        isShowing = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.isShowing == false else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func close() {
        hiddenCall = app.call?.call
        hide()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        let view = NSHostingView(rootView: CallPanelView { [weak self] in self?.close() }.environmentObject(app))
        view.sizingOptions = [.intrinsicContentSize]
        panel.contentView = view
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let view = panel.contentView else { return }
        let size = view.fittingSize
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.maxX - size.width, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}
