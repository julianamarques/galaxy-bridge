import Foundation

extension ADB {
    public static func battery(serial: String) async -> Battery? {
        guard let result = try? await run(["-s", serial, "shell", "dumpsys", "battery"], timeout: 8) else { return nil }
        return Battery(dumpsys: result.stdout)
    }

    /// O país em que o Galaxy está, pela rede da operadora (muda em roaming); sem sinal, o país do chip.
    /// São códigos ISO, como `br`. Com dois chips, o Android separa os países por vírgula.
    public static func phoneCountry(serial: String) async -> String? {
        for property in ["gsm.operator.iso-country", "gsm.sim.operator.iso-country"] {
            guard let result = try? await run(["-s", serial, "shell", "getprop", property], timeout: 8) else { continue }
            if let country = firstCountry(result.stdout) { return country }
        }
        return nil
    }

    static func firstCountry(_ output: String) -> String? {
        output
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count == 2 }
    }

    public static func call(_ number: PhoneNumber, serial: String) async throws {
        // O adb junta os argumentos num comando do shell do Android; as aspas evitam que `*` e `;` sejam interpretados.
        let result = try await run(
            ["-s", serial, "shell", "am", "start", "-a", "android.intent.action.CALL", "-d", "'\(number.telURI)'"],
            timeout: 10
        )
        guard !result.output.contains("Error") else {
            throw ToolError.failed([String(localized: "O Galaxy não conseguiu iniciar a ligação."), result.output].joined(separator: "\n"))
        }
    }

    public static func endCall(serial: String) async {
        _ = try? await run(["-s", serial, "shell", "input", "keyevent", "KEYCODE_ENDCALL"], timeout: 5)
    }
}
