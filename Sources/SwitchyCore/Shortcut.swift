import Foundation

/// A regular key plus modifiers, e.g. ⌥1.
public struct KeyCombo: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ModifierPattern

    public init(keyCode: UInt16, modifiers: ModifierPattern) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        let key = KeyCode.name(for: keyCode)
        if modifiers.isEmpty { return key }
        return modifiers.isCompactDisplay
            ? modifiers.displayString + key
            : modifiers.displayString + " + " + key
    }
}

public enum Shortcut: Hashable, Codable, Sendable {
    /// Fires on key down; the key event is swallowed so it never reaches the app.
    case keyCombo(KeyCombo)
    /// Fires when the modifiers are released without any other key or click in between.
    case modifierTap(ModifierPattern)

    public var displayString: String {
        switch self {
        case .keyCombo(let combo): combo.displayString
        case .modifierTap(let pattern): pattern.displayString
        }
    }

    public var isModifierTap: Bool {
        if case .modifierTap = self { return true }
        return false
    }

    public var isSideSpecific: Bool {
        switch self {
        case .keyCombo(let combo): combo.modifiers.isSideSpecific
        case .modifierTap(let pattern): pattern.isSideSpecific
        }
    }

    public var eitherSide: Shortcut {
        switch self {
        case .keyCombo(var combo):
            combo.modifiers = combo.modifiers.eitherSide
            return .keyCombo(combo)
        case .modifierTap(let pattern):
            return .modifierTap(pattern.eitherSide)
        }
    }

    /// True if one physical key press could trigger both shortcuts.
    public func overlaps(_ other: Shortcut) -> Bool {
        switch (self, other) {
        case let (.keyCombo(a), .keyCombo(b)):
            a.keyCode == b.keyCode && a.modifiers.overlaps(b.modifiers, function: .ignoreUnlessRequired)
        case let (.modifierTap(a), .modifierTap(b)):
            a.overlaps(b, function: .exact)
        default:
            false
        }
    }
}
