import Foundation
import PhoneNumberKit

@MainActor
public final class PhoneNumbers {
    public static let shared = PhoneNumbers()

    private let utility = PhoneNumberUtility()
    private var partialFormatters: [String: PartialFormatter] = [:]

    public init() {}

    public func formatPartial(_ text: String, country: String?) -> String {
        guard let region = Self.region(country), !text.isEmpty, !PhoneNumber.isName(text) else { return text }
        let isInternational = text.hasPrefix("+")
        if let parsed = try? utility.parse(text, withRegion: region) {
            return utility.format(parsed, toType: isInternational ? .international : .national)
        }
        guard !text.contains(where: { "*#,;".contains($0) }) else { return text }
        let digits = (isInternational ? "+" : "") + text.filter(\.isNumber)
        let partial = partialFormatter(for: region).formatPartial(digits)
        return region == "BR" && !isInternational ? Self.parenthesizeAreaCode(partial) : partial
    }

    private static func parenthesizeAreaCode(_ text: String) -> String {
        text.replacingOccurrences(of: #"^(\d{2}) (\d)"#, with: "($1) $2", options: .regularExpression)
    }

    public func dialable(_ number: PhoneNumber, country: String?) -> PhoneNumber {
        guard let region = Self.region(country),
              let parsed = try? utility.parse(number.digits, withRegion: region),
              let international = PhoneNumber(utility.format(parsed, toType: .e164))
        else { return number }
        return international
    }

    public func display(_ text: String, country: String?) -> String {
        guard let region = Self.region(country), let parsed = try? utility.parse(text, withRegion: region) else { return text }
        let isLocal = parsed.regionID == region
        return utility.format(parsed, toType: isLocal ? .national : .international)
    }

    private func partialFormatter(for region: String) -> PartialFormatter {
        if let formatter = partialFormatters[region] { return formatter }
        let formatter = PartialFormatter(utility: utility, defaultRegion: region, withPrefix: true)
        partialFormatters[region] = formatter
        return formatter
    }

    private static func region(_ country: String?) -> String? {
        guard let country, country.count == 2 else { return nil }
        return country.uppercased()
    }
}
