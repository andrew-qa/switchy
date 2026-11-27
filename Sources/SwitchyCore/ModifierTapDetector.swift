import Foundation

/// Detects a "clean" modifier-only press: one or more modifiers go down and all come back up
/// with no other key, click or scroll in between, within `maxTapDuration`.
///
/// This is what makes "tap Right ⌘" safe: ⌘C, ⌘-click, ⌘-scroll and holding ⌘ while
/// thinking never count as a tap.
public struct ModifierTapDetector: Sendable {
    public var maxTapDuration: TimeInterval

    public private(set) var pressed: ModifierKeys = []
    private var chord: ModifierKeys = []
    private var chordStart: TimeInterval = 0
    private var spoiled = false

    public init(maxTapDuration: TimeInterval) {
        self.maxTapDuration = maxTapDuration
    }

    /// Feed the full set of currently held modifiers. Returns the chord when a clean tap completes.
    public mutating func modifiersChanged(to newPressed: ModifierKeys, at time: TimeInterval) -> ModifierKeys? {
        let old = pressed
        pressed = newPressed

        if old.isEmpty {
            if !newPressed.isEmpty {
                chord = newPressed
                chordStart = time
                spoiled = false
            }
            return nil
        }
        if !newPressed.isEmpty {
            chord.formUnion(newPressed)
            return nil
        }

        // Everything released.
        defer {
            chord = []
            spoiled = false
        }
        guard !spoiled, time - chordStart <= maxTapDuration else { return nil }
        return chord
    }

    /// Any non-modifier input (key, click, scroll) while modifiers are held cancels the tap.
    public mutating func noteOtherInput() {
        if !pressed.isEmpty { spoiled = true }
    }

    /// Start over. A chord already in progress is ignored, so it can't complete half-seen.
    public mutating func reset() {
        chord = pressed
        spoiled = !pressed.isEmpty
    }
}
