import AppKit
import SwiftUI

extension OpenWindowAction {
    @MainActor
    func activating(id: String) {
        callAsFunction(id: id)
        NSApp.activate()
    }
}
