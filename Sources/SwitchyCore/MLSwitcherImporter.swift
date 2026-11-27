import Foundation

/// Reads MLSwitcher2's per-layout shortcuts so switching apps doesn't mean re-recording them.
public enum MLSwitcherImporter {
    public static let bundleID = "com.bluezbox.MLSwitcher2"

    /// MLSwitcher2 stores each layout's shortcut under the input source ID as
    /// `NSEvent.ModifierFlags.rawValue | keyCode`. Example: 524306 = 0x80012 = ⌥ (1 << 19) + key 18 ("1").
    public static func decodeShortcut(_ value: Int) -> Shortcut? {
        guard value > 0 else { return nil }
        let keyCode = value & 0xFFFF
        let flags = value & ~0xFFFF
        guard keyCode < 128, flags != 0 else { return nil }

        var mods = ModifierPattern()
        if flags & (1 << 17) != 0 { mods.shift = .either }
        if flags & (1 << 18) != 0 { mods.control = .either }
        if flags & (1 << 19) != 0 { mods.option = .either }
        if flags & (1 << 20) != 0 { mods.command = .either }
        if flags & (1 << 23) != 0 { mods.function = true }
        guard !mods.isEmpty else { return nil }
        return .keyCombo(KeyCombo(keyCode: UInt16(keyCode), modifiers: mods))
    }

    /// Only layouts that are still enabled are imported, in a stable order.
    public static func bindings(from preferences: [String: Any], enabledSourceIDs: Set<String>) -> [ShortcutBinding] {
        preferences.keys.sorted().compactMap { key in
            guard enabledSourceIDs.contains(key),
                  let value = preferences[key] as? Int,
                  let shortcut = decodeShortcut(value)
            else { return nil }
            return ShortcutBinding(action: .select(sourceID: key), shortcut: shortcut, matchEitherSide: true)
        }
    }

    public static func readPreferences() -> [String: Any]? {
        UserDefaults.standard.persistentDomain(forName: bundleID)
    }
}
