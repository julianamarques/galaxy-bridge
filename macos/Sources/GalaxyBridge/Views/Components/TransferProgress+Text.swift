import BridgeProtocol
import Foundation

extension TransferProgress {
    var status: String {
        if done == 0, direction == .toPhone { return String(localized: "Aguardando…") }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    func label(device: String) -> String {
        direction == .toPhone ? String(localized: "Enviando para o \(device)") : String(localized: "Recebendo do \(device)")
    }
}
