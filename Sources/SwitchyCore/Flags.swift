import Foundation

public struct FlagRegion: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let emoji: String
    public var id: String { code }
}

/// Emoji flags for keyboard layouts.
public enum FlagEmoji {
    /// "UA" → 🇺🇦. Flags are pairs of regional-indicator letters, so any two-letter region code works.
    public static func emoji(forRegion code: String) -> String? {
        let upper = code.uppercased()
        guard upper.unicodeScalars.count == 2,
              upper.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 })
        else { return nil }
        var flag = String.UnicodeScalarView()
        for letter in upper.unicodeScalars {
            guard let indicator = Unicode.Scalar(0x1F1E6 + letter.value - 65) else { return nil }
            flag.append(indicator)
        }
        return String(flag)
    }

    /// The country a layout most likely stands for. The layout's own name wins where it is more
    /// specific than its language (British → GB, not en → US); otherwise the language's main country.
    public static func automaticRegion(sourceID: String, languageCode: String?) -> String? {
        let layoutName = sourceID.split(separator: ".").last.map(String.init) ?? sourceID
        if let hinted = layoutRegionHints[layoutName] { return hinted }
        guard let languageCode, !languageCode.isEmpty else { return nil }
        let maximal = Locale.Language(identifier: languageCode).maximalIdentifier
        guard let region = Locale.Language(identifier: maximal).region?.identifier,
              emoji(forRegion: region) != nil
        else { return nil }
        return region
    }

    /// Every region that has a flag, sorted by its name in `locale`.
    public static func allRegions(locale: Locale = .current) -> [FlagRegion] {
        Locale.Region.isoRegions.compactMap { region -> FlagRegion? in
            let code = region.identifier
            guard let emoji = emoji(forRegion: code), let name = locale.localizedString(forRegionCode: code) else { return nil }
            return FlagRegion(code: code, name: name, emoji: emoji)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Apple layout names (last part of the input source ID) that pin a country.
    static let layoutRegionHints: [String: String] = [
        "US": "US", "USExtended": "US", "USInternational-PC": "US",
        "British": "GB", "British-PC": "GB",
        "Irish": "IE", "IrishExtended": "IE",
        "Australian": "AU",
        "Canadian": "CA", "Canadian-CSA": "CA", "CanadianFrench-PC": "CA",
        "SwissGerman": "CH", "SwissFrench": "CH",
        "Austrian": "AT",
        "Belgian": "BE",
        "Brazilian": "BR", "Brazilian-ABNT2": "BR", "Brazilian-Pro": "BR",
    ]
}
