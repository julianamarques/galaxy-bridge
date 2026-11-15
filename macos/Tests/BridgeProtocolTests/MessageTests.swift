import Foundation
import Testing
@testable import BridgeProtocol

struct FixtureTests {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("protocol/fixtures")

    static var fixtures: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.filter { $0.hasSuffix(".json") }.sorted() ?? []
    }

    @Test func fixturesExist() {
        #expect(Self.fixtures.count >= 40)
    }

    @Test(arguments: fixtures)
    func roundTrips(_ name: String) throws {
        let data = try Data(contentsOf: Self.directory.appendingPathComponent(name))
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if case .unknown = envelope.message { Issue.record("\(name) não foi reconhecida") }
        #expect(name.hasPrefix(envelope.message.type + "."))

        let original = try JSONSerialization.jsonObject(with: data) as! NSDictionary
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as! NSDictionary
        #expect(original == reencoded)
    }
}

struct MessageTests {
    @Test func ignoresUnknownTypesAndFields() throws {
        let json = #"{"type":"future.thing","body":{"x":1}}"#
        #expect(try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).message == .unknown(type: "future.thing"))

        let status = #"{"type":"status","body":{"battery":{"level":5,"charging":true,"temperature":30},"wifi":"x"}}"#
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(status.utf8))
        #expect(envelope.message == .status(PhoneStatus(battery: .init(level: 5, charging: true))))
    }

    @Test func leavesOutEmptyFields() throws {
        let json = String(decoding: try JSONEncoder().encode(Envelope(.ping)), as: UTF8.self)
        #expect(json == #"{"type":"ping"}"#)
    }
}

struct FrameTests {
    @Test func decodesMessagesSplitAcrossReads() throws {
        let first = try Frame.encode(Envelope(.ping))
        let second = try Frame.encode(Envelope(.callPlace(CallPlace(number: "+5586999990001")), id: "1"))
        let stream = first + second
        var decoder = FrameDecoder()
        var bodies: [Data] = []
        for byte in stream {
            bodies += try decoder.append(Data([byte]))
        }
        #expect(bodies == [first.dropFirst(4), second.dropFirst(4)].map { Data($0) })
    }

    @Test func decodesSeveralMessagesInOneRead() throws {
        let data = try Frame.encode(Envelope(.ping)) + Frame.encode(Envelope(.pong))
        var decoder = FrameDecoder()
        #expect(try decoder.append(data).count == 2)
    }

    @Test func rejectsOversizedLength() {
        var decoder = FrameDecoder()
        #expect(throws: Frame.Failure.tooLong(0x0200_0000)) {
            try decoder.append(Data([0x02, 0x00, 0x00, 0x00, 0x7b]))
        }
    }
}
