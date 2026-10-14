import Testing
@testable import GalaxyKit

@MainActor
struct PhoneNumbersTests {
    private let numbers = PhoneNumbers()

    private func typing(_ keys: String, country: String) -> String {
        var text = ""
        for key in keys { text = numbers.formatPartial(text + String(key), country: country) }
        return text
    }

    private func dialable(_ text: String, country: String?) -> String? {
        PhoneNumber(text).map { numbers.dialable($0, country: country).digits }
    }

    @Test func formatsWhileTyping() {
        #expect(typing("86999990001", country: "br") == "(86) 99999-0001")
        #expect(typing("8632211234", country: "br") == "(86) 3221-1234")
        #expect(typing("4155550100", country: "us") == "(415) 555-0100")
        #expect(typing("+5586999990001", country: "us") == "+55 86 99999-0001")
        #expect(typing("08001234567", country: "br") == "0800 123 4567")
        #expect(numbers.formatPartial("86 99999.0001", country: "br") == "(86) 99999-0001")
    }

    @Test func keepsBrazilianAreaCodeInParenthesesWhileTyping() {
        #expect(typing("8699", country: "br") == "(86) 99")
        #expect(typing("8699999000", country: "br") == "(86) 99999-000")
        #expect(typing("86", country: "br") == "86")
    }

    @Test func leavesTextAloneWithoutCountry() {
        #expect(numbers.formatPartial("86999990001", country: nil) == "86999990001")
    }

    @Test func dialsBrazilianNumbersInInternationalFormat() {
        #expect(dialable("(86) 99999-0001", country: "br") == "+5586999990001")
        #expect(dialable("+55 86 99999-0001", country: "br") == "+5586999990001")
    }

    @Test func usesTheCountryWhereThePhoneIs() {
        #expect(dialable("(415) 555-0100", country: "us") == "+14155550100")
        #expect(dialable("+55 86 99999-0001", country: "us") == "+5586999990001")
    }

    @Test func keepsNumbersItCannotPlace() {
        #expect(dialable("99999-0001", country: "br") == "999990001")
        #expect(dialable("190", country: "br") == "190")
        #expect(dialable("*144#", country: "br") == "*144#")
        #expect(dialable("(86) 99999-0001", country: nil) == "86999990001")
    }
}
