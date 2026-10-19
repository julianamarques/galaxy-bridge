import AppKit
import GalaxyKit
import SwiftUI

struct PhoneField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let country: String?
    let onSubmit: () -> Void
    let onMove: (Int) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PhoneField

        init(parent: PhoneField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let formatted = PhoneNumbers.shared.formatPartial(field.stringValue, country: parent.country)
            if formatted != field.stringValue { field.stringValue = formatted }
            parent.text = formatted
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            default:
                return false
            }
            return true
        }
    }
}
