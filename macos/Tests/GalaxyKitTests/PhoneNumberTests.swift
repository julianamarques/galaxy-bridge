import Foundation
import Testing
@testable import GalaxyKit

struct PhoneNumberTests {
    @Test func keepsOnlyDialableCharacters() {
        #expect(PhoneNumber("+55 (11) 99999-0000")?.digits == "+5511999990000")
    }

    @Test func treatsTypedTextWithLettersAsAName() {
        #expect(PhoneNumber(typed: "Ana 2") == nil)
        #expect(PhoneNumber(typed: "(86) 99999-0001")?.digits == "86999990001")
    }

    @Test func rejectsTextWithoutDigits() {
        #expect(PhoneNumber("Maria") == nil)
        #expect(PhoneNumber("+") == nil)
    }

    @Test func dropsShellCharacters() {
        #expect(PhoneNumber("123'; reboot; '")?.digits == "123;;")
    }

    @Test func readsTelURLs() throws {
        #expect(PhoneNumber(url: try #require(URL(string: "tel:+5511999990000")))?.digits == "+5511999990000")
        #expect(PhoneNumber(url: try #require(URL(string: "tel://011%2099999-0000")))?.digits == "01199999-0000".filter(\.isNumber))
        #expect(PhoneNumber(url: try #require(URL(string: "tel:+5511999990000;ext=12")))?.digits == "+5511999990000")
        #expect(PhoneNumber(url: try #require(URL(string: "https://example.com/123"))) == nil)
    }

    @Test func encodesHashInURI() {
        #expect(PhoneNumber("*144#")?.telURI == "tel:*144%23")
    }
}

