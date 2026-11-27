import Foundation

public enum SwitchAction: Hashable, Codable, Sendable {
    case select(sourceID: String)
    case next
    case previous
}

public struct ShortcutBinding: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var action: SwitchAction
    /// The shortcut exactly as recorded, sides included, so toggling `matchEitherSide` is lossless.
    public var shortcut: Shortcut
    public var matchEitherSide: Bool

    /// By default key combos accept either side (⌥1 with any ⌥), while modifier taps keep
    /// the recorded side, since telling Left ⌘ from Right ⌘ is usually the point of them.
    public init(id: UUID = UUID(), action: SwitchAction, shortcut: Shortcut, matchEitherSide: Bool? = nil) {
        self.id = id
        self.action = action
        self.shortcut = shortcut
        self.matchEitherSide = matchEitherSide ?? !shortcut.isModifierTap
    }

    /// What the engine actually matches against.
    public var effectiveShortcut: Shortcut {
        matchEitherSide ? shortcut.eitherSide : shortcut
    }
}

public enum BindingList {
    /// The bindings that should be live. A shortcut for a layout that's no longer enabled stays
    /// saved, so it comes back if the layout does, but it must not eat its keys meanwhile.
    public static func active(_ bindings: [ShortcutBinding], enabledSourceIDs: Set<String>) -> [ShortcutBinding] {
        bindings.filter { binding in
            switch binding.action {
            case .select(let id): enabledSourceIDs.contains(id)
            case .next, .previous: true
            }
        }
    }

    /// IDs of bindings that could fire on the same key press as another binding.
    public static func conflictingIDs(_ bindings: [ShortcutBinding]) -> Set<UUID> {
        var result = Set<UUID>()
        for i in bindings.indices {
            for j in bindings.indices
            where j > i && bindings[i].effectiveShortcut.overlaps(bindings[j].effectiveShortcut) {
                result.insert(bindings[i].id)
                result.insert(bindings[j].id)
            }
        }
        return result
    }

    public static func encode(_ bindings: [ShortcutBinding]) throws -> Data {
        try JSONEncoder().encode(bindings)
    }

    /// Corrupt or outdated data yields an empty list rather than a crash at launch.
    public static func decode(_ data: Data?) -> [ShortcutBinding] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ShortcutBinding].self, from: data)) ?? []
    }
}
