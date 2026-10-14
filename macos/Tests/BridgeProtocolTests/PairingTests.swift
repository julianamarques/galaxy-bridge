import Foundation
import Testing
@testable import BridgeProtocol

struct PairingSessionTests {
    @Test func acceptsTokenOrCode() {
        var session = PairingSession()
        #expect(session.check(session.token) == .accepted)
        var other = PairingSession()
        #expect(other.check(other.code) == .accepted)
    }

    @Test func makesUnguessableToken() {
        let session = PairingSession()
        #expect(session.token.count == 22)
        #expect(session.code.count == 6)
        #expect(session.code.allSatisfy { $0.isNumber })
        #expect(PairingSession().token != session.token)
    }

    @Test func expiresAfterTwoMinutes() {
        let start = Date()
        var session = PairingSession(now: start)
        #expect(session.check(session.code, now: start.addingTimeInterval(119)) == .accepted)
        #expect(session.check(session.code, now: start.addingTimeInterval(120)) == .expired)
    }

    @Test func expiresAfterFiveWrongCodes() {
        var session = PairingSession()
        let wrong = session.code == "000000" ? "000001" : "000000"
        for _ in 1..<PairingSession.maxCodeAttempts {
            #expect(session.check(wrong) == .invalid)
        }
        #expect(session.check(wrong) == .expired)
        #expect(session.check(session.code) == .expired)
    }
}

struct PairingLinkTests {
    let link = PairingLink(host: "192.168.1.20", port: 52800, fingerprint: String(repeating: "ab", count: 32), token: "q3HcKk0b5mJ8b1yZ1Xr7Ag")

    @Test func roundTrips() {
        #expect(link.url.absoluteString.hasPrefix("galaxybridge://pair?v=1&host=192.168.1.20&port=52800&fp=abab"))
        #expect(PairingLink(url: link.url) == link)
    }

    @Test func rejectsOtherVersionsAndBrokenLinks() {
        let other = URL(string: link.url.absoluteString.replacingOccurrences(of: "v=1", with: "v=2"))!
        #expect(PairingLink(url: other) == nil)
        #expect(PairingLink(url: URL(string: "galaxybridge://pair?v=1&host=x&port=1")!) == nil)
        #expect(PairingLink(url: URL(string: "https://example.com")!) == nil)
    }
}

@MainActor
struct PairingStoreTests {
    @Test func persistsPhones() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pairing-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let phone = PairedPhone(fingerprint: "ab", name: "Galaxy S25", model: "SM-S931B", pairedAt: Date(timeIntervalSince1970: 0))
        PairingStore(file: file).save(phone)

        let store = PairingStore(file: file)
        #expect(store.phones == [phone])
        store.remove(fingerprint: "ab")
        #expect(PairingStore(file: file).phones.isEmpty)
    }
}

struct IdentityTests {
    @Test func keepsTheSameIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try Identity.loadOrCreate(in: directory)
        let second = try Identity.loadOrCreate(in: directory)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.fingerprint.count == 64)

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("key.raw").path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    @Test func formatsFingerprintForPeople() {
        #expect(Fingerprint.display("3f2a9c01b7e4d5") == "3F2A 9C01 B7E4")
        #expect(Fingerprint.shortID(String(repeating: "a", count: 64)).count == 16)
    }
}
