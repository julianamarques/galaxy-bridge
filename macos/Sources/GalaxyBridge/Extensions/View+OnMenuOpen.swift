import AppKit
import SwiftUI

extension View {
    func onMenuOpen(_ action: @escaping () -> Void) -> some View {
        background(MenuOpenObserver(action: action))
    }
}

private struct MenuOpenObserver: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(action: action)
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.action = action
    }

    final class ObserverView: NSView {
        var action: () -> Void
        private var token: NSObjectProtocol?

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            token.map(NotificationCenter.default.removeObserver)
            token = nil
            guard let window else { return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.action() }
            }
            if window.isKeyWindow { action() }
        }
    }
}
