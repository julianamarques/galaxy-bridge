import Foundation
import Testing
@testable import BridgeProtocol

struct TransferTests {
    @Test func keepsOrdinaryNames() {
        #expect(Transfer.safeName("IMG_2041.jpg") == "IMG_2041.jpg")
        #expect(Transfer.safeName("Relatório final.pdf") == "Relatório final.pdf")
    }

    @Test func dropsPathsAndHiddenNames() {
        #expect(Transfer.safeName("../../.ssh/authorized_keys") == "authorized_keys")
        #expect(Transfer.safeName("/etc/passwd") == "passwd")
        #expect(Transfer.safeName(".bashrc") == "bashrc")
        #expect(Transfer.safeName("a\\b:c.txt") == "c.txt")
        #expect(Transfer.safeName("..") == "Arquivo do Galaxy")
        #expect(Transfer.safeName("") == "Arquivo do Galaxy")
    }

    @Test func numbersCopiesInsteadOfReplacing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func incoming() throws -> URL {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data("x".utf8).write(to: file)
            return file
        }
        #expect(try Transfer.place(incoming(), named: "foto.jpg", in: directory).lastPathComponent == "foto.jpg")
        #expect(try Transfer.place(incoming(), named: "foto.jpg", in: directory).lastPathComponent == "foto (1).jpg")
        #expect(try Transfer.place(incoming(), named: "foto.jpg", in: directory).lastPathComponent == "foto (2).jpg")
        #expect(try Transfer.place(incoming(), named: "LEIAME", in: directory).lastPathComponent == "LEIAME")
        #expect(try Transfer.place(incoming(), named: "LEIAME", in: directory).lastPathComponent == "LEIAME (1)")
    }
}
