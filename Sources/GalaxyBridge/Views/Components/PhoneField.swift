import AppKit
import GalaxyKit
import SwiftUI

/// Campo de telefone com máscara. O `TextField` do SwiftUI no macOS não mostra mudanças feitas no texto
/// enquanto ele está sendo editado, então a máscara é aplicada direto no `NSTextField`.
struct PhoneField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let country: String?
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        // Mesma altura dos botões redondos ao lado, que usam o tamanho grande.
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
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}
