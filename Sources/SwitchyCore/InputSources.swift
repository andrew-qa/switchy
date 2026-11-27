import Carbon
import Foundation

public struct InputSourceInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let languageCode: String?
    public let iconURL: URL?

    public init(id: String, name: String, languageCode: String?, iconURL: URL?) {
        self.id = id
        self.name = name
        self.languageCode = languageCode
        self.iconURL = iconURL
    }

    /// Two-letter menu bar label. Ukrainian's language code "uk" reads as Britain, so it shows "UA".
    public var shortLabel: String {
        if let code = languageCode?.split(separator: "-").first?.lowercased(), !code.isEmpty {
            return (Self.labelOverrides[code] ?? code).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    static let labelOverrides: [String: String] = ["uk": "ua"]
}

/// Reads the enabled keyboard input sources, in the order the system input menu shows them.
public enum InputSourceCatalog {
    public static func enabledKeyboardSources() -> [InputSourceInfo] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.compactMap { source in
            // An input method's parent entry isn't selectable as such; its modes are listed separately.
            let type: String? = property(source, kTISPropertyInputSourceType)
            if type == (kTISTypeKeyboardInputMethodModeEnabled as String) { return nil }
            guard let id: String = property(source, kTISPropertyInputSourceID) else { return nil }
            let languages: [String]? = property(source, kTISPropertyInputSourceLanguages)
            return InputSourceInfo(
                id: id,
                name: property(source, kTISPropertyLocalizedName) ?? id,
                languageCode: languages?.first,
                iconURL: property(source, kTISPropertyIconImageURL)
            )
        }
    }

    static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }
}

/// The real backend. Looks the source up by ID on every call instead of caching handles,
/// because cached `TISInputSourceRef`s can go stale after sleep or layout changes.
@MainActor
public final class TISInputSourceBackend: InputSourceBackend {
    public init() {}

    public func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return InputSourceCatalog.property(source, kTISPropertyInputSourceID)
    }

    public func selectSource(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first
        else { return false }
        return TISSelectInputSource(source) == noErr
    }
}
