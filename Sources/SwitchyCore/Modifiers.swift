import Foundation

/// The four modifier kinds that exist on both sides of a Mac keyboard, in Apple's display order (⌃⌥⇧⌘).
public enum ModifierKind: String, CaseIterable, Codable, Sendable {
    case control, option, shift, command

    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
}

/// Physical modifier keys that are currently held, with left and right told apart.
public struct ModifierKeys: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let leftControl = ModifierKeys(rawValue: 1 << 0)
    public static let rightControl = ModifierKeys(rawValue: 1 << 1)
    public static let leftOption = ModifierKeys(rawValue: 1 << 2)
    public static let rightOption = ModifierKeys(rawValue: 1 << 3)
    public static let leftShift = ModifierKeys(rawValue: 1 << 4)
    public static let rightShift = ModifierKeys(rawValue: 1 << 5)
    public static let leftCommand = ModifierKeys(rawValue: 1 << 6)
    public static let rightCommand = ModifierKeys(rawValue: 1 << 7)
    public static let function = ModifierKeys(rawValue: 1 << 8)

    public static func left(_ kind: ModifierKind) -> ModifierKeys {
        switch kind {
        case .control: .leftControl
        case .option: .leftOption
        case .shift: .leftShift
        case .command: .leftCommand
        }
    }

    public static func right(_ kind: ModifierKind) -> ModifierKeys {
        switch kind {
        case .control: .rightControl
        case .option: .rightOption
        case .shift: .rightShift
        case .command: .rightCommand
        }
    }

    public func sides(of kind: ModifierKind) -> (left: Bool, right: Bool) {
        (contains(.left(kind)), contains(.right(kind)))
    }

    public var withoutFunction: ModifierKeys { subtracting(.function) }
}

/// Bit layout shared by `CGEventFlags` and `NSEvent.ModifierFlags` (IOKit's NX_* masks).
/// Device-independent bits say *that* a modifier is down; device-dependent bits say *which side*.
enum EventFlagLayout {
    static let function: UInt64 = 0x0080_0000

    static func bits(for kind: ModifierKind) -> (independent: UInt64, left: UInt64, right: UInt64) {
        switch kind {
        case .control: (0x0004_0000, 0x0000_0001, 0x0000_2000)
        case .option: (0x0008_0000, 0x0000_0020, 0x0000_0040)
        case .shift: (0x0002_0000, 0x0000_0002, 0x0000_0004)
        case .command: (0x0010_0000, 0x0000_0008, 0x0000_0010)
        }
    }

    /// Inverse of `ModifierKeys(eventFlags:)`, used to build realistic events in tests.
    static func eventFlags(for keys: ModifierKeys) -> UInt64 {
        var raw: UInt64 = 0
        for kind in ModifierKind.allCases {
            let b = bits(for: kind)
            let s = keys.sides(of: kind)
            if s.left { raw |= b.independent | b.left }
            if s.right { raw |= b.independent | b.right }
        }
        if keys.contains(.function) { raw |= function }
        return raw
    }
}

extension ModifierKeys {
    /// Decodes the raw value of `CGEventFlags` or `NSEvent.ModifierFlags`.
    /// Caps Lock, numeric-pad and other non-modifier bits are ignored.
    public init(eventFlags raw: UInt64) {
        var keys: ModifierKeys = []
        for kind in ModifierKind.allCases {
            let b = EventFlagLayout.bits(for: kind)
            // Trust the device-independent bit; side bits can linger after release on some keyboards.
            guard raw & b.independent != 0 else { continue }
            let left = raw & b.left != 0
            let right = raw & b.right != 0
            if left { keys.insert(.left(kind)) }
            if right { keys.insert(.right(kind)) }
            // Virtual keyboards (remote desktop, some remappers) omit side bits entirely.
            if !left && !right { keys.insert(.left(kind)) }
        }
        if raw & EventFlagLayout.function != 0 { keys.insert(.function) }
        self = keys
    }
}

/// What a shortcut demands of one modifier kind.
public enum SideRequirement: String, CaseIterable, Codable, Sendable {
    case none, either, left, right, both

    public func isSatisfied(left: Bool, right: Bool) -> Bool {
        switch self {
        case .none: !left && !right
        case .either: left || right
        case .left: left && !right
        case .right: right && !left
        case .both: left && right
        }
    }

    /// True if some physical state of this modifier satisfies both requirements.
    func canCoexist(with other: SideRequirement) -> Bool {
        for left in [false, true] {
            for right in [false, true]
            where isSatisfied(left: left, right: right) && other.isSatisfied(left: left, right: right) {
                return true
            }
        }
        return false
    }
}

/// The modifier part of a shortcut, e.g. "⌥", "Right ⌘", "Left ⌥ + Left ⇧".
public struct ModifierPattern: Hashable, Codable, Sendable {
    public var control: SideRequirement
    public var option: SideRequirement
    public var shift: SideRequirement
    public var command: SideRequirement
    public var function: Bool

    public init(
        control: SideRequirement = .none,
        option: SideRequirement = .none,
        shift: SideRequirement = .none,
        command: SideRequirement = .none,
        function: Bool = false
    ) {
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
        self.function = function
    }

    /// A pattern that requires exactly these physical keys (sides included).
    public init(exactly keys: ModifierKeys) {
        self.init(function: keys.contains(.function))
        for kind in ModifierKind.allCases {
            let s = keys.sides(of: kind)
            self[kind] = switch (s.left, s.right) {
            case (true, true): .both
            case (true, false): .left
            case (false, true): .right
            case (false, false): .none
            }
        }
    }

    public subscript(kind: ModifierKind) -> SideRequirement {
        get {
            switch kind {
            case .control: control
            case .option: option
            case .shift: shift
            case .command: command
            }
        }
        set {
            switch kind {
            case .control: control = newValue
            case .option: option = newValue
            case .shift: shift = newValue
            case .command: command = newValue
            }
        }
    }

    public var isEmpty: Bool {
        !function && ModifierKind.allCases.allSatisfy { self[$0] == .none }
    }

    public var isSideSpecific: Bool {
        ModifierKind.allCases.contains { [.left, .right, .both].contains(self[$0]) }
    }

    /// Same modifiers, but either side of each one will do.
    public var eitherSide: ModifierPattern {
        var p = self
        for kind in ModifierKind.allCases where p[kind] != .none { p[kind] = .either }
        return p
    }

    public enum FunctionPolicy: Sendable {
        /// fn must be held exactly when the pattern says so (modifier taps).
        case exact
        /// fn only matters if the pattern requires it. macOS sets the fn flag on its own for
        /// arrows, F-keys, Home/End etc., so key combos must not reject those events.
        case ignoreUnlessRequired
    }

    public func matches(_ keys: ModifierKeys, function policy: FunctionPolicy = .exact) -> Bool {
        for kind in ModifierKind.allCases {
            let s = keys.sides(of: kind)
            guard self[kind].isSatisfied(left: s.left, right: s.right) else { return false }
        }
        switch policy {
        case .exact: return function == keys.contains(.function)
        case .ignoreUnlessRequired: return !function || keys.contains(.function)
        }
    }

    /// True if some physical key state would match both patterns.
    public func overlaps(_ other: ModifierPattern, function policy: FunctionPolicy = .exact) -> Bool {
        if policy == .exact && function != other.function { return false }
        return ModifierKind.allCases.allSatisfy { self[$0].canCoexist(with: other[$0]) }
    }

    /// Display tokens in Apple order: compact ("⌃⌥⇧") unless sides or fn need words.
    var displayTokens: [String] {
        var tokens: [String] = function ? ["fn"] : []
        for kind in ModifierKind.allCases {
            switch self[kind] {
            case .none: break
            case .either: tokens.append(kind.symbol)
            case .left: tokens.append("Left \(kind.symbol)")
            case .right: tokens.append("Right \(kind.symbol)")
            case .both: tokens.append("Both \(kind.symbol)")
            }
        }
        return tokens
    }

    var isCompactDisplay: Bool { displayTokens.allSatisfy { $0.count == 1 } }

    public var displayString: String {
        displayTokens.joined(separator: isCompactDisplay ? "" : " + ")
    }
}
