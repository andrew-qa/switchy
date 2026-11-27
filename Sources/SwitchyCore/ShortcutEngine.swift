import Foundation

/// Keyboard/mouse input, already decoded from `CGEvent`.
public enum EngineEvent: Equatable, Sendable {
    case keyDown(keyCode: UInt16, modifiers: ModifierKeys, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
    case modifiersChanged(ModifierKeys)
    /// Mouse click or scroll. Only matters for cancelling modifier taps.
    case otherInput
}

public enum EngineEffect: Equatable, Sendable {
    case perform(SwitchAction)
    case recorded(Shortcut)
    case recordingCancelled
}

public struct EngineResult: Equatable, Sendable {
    /// Drop the event so the frontmost app never sees it.
    public var swallow: Bool
    public var effect: EngineEffect?

    public init(swallow: Bool, effect: EngineEffect? = nil) {
        self.swallow = swallow
        self.effect = effect
    }

    public static let pass = EngineResult(swallow: false)
    public static let swallowed = EngineResult(swallow: true)
}

/// The decision core of the event tap: given an input event, should it be swallowed, and
/// should something happen? Pure value type so every rule is unit-tested without a real tap.
public struct ShortcutEngine: Sendable {
    public static let defaultMaxTapDuration: TimeInterval = 0.6
    static let recordingMaxTapDuration: TimeInterval = 5

    private var combos: [(combo: KeyCombo, action: SwitchAction)] = []
    private var taps: [(pattern: ModifierPattern, action: SwitchAction)] = []
    private var tapDetector: ModifierTapDetector
    private var recordDetector = ModifierTapDetector(maxTapDuration: recordingMaxTapDuration)
    /// Keys whose key-down we swallowed; their key-up must be swallowed too.
    private var swallowedKeyUps: Set<UInt16> = []
    public private(set) var isRecording = false

    public init(bindings: [ShortcutBinding] = [], maxTapDuration: TimeInterval = defaultMaxTapDuration) {
        tapDetector = ModifierTapDetector(maxTapDuration: maxTapDuration)
        configure(bindings: bindings, maxTapDuration: maxTapDuration)
    }

    /// First binding wins when shortcuts overlap; the settings UI flags such conflicts.
    public mutating func configure(bindings: [ShortcutBinding], maxTapDuration: TimeInterval) {
        combos = []
        taps = []
        for binding in bindings {
            switch binding.effectiveShortcut {
            case .keyCombo(let combo): combos.append((combo, binding.action))
            case .modifierTap(let pattern): taps.append((pattern, binding.action))
            }
        }
        tapDetector.maxTapDuration = maxTapDuration
    }

    /// While recording, shortcuts don't fire and the captured keys don't reach any app.
    public mutating func startRecording() {
        isRecording = true
        recordDetector.reset()
    }

    public mutating func cancelRecording() {
        isRecording = false
    }

    public mutating func handle(_ event: EngineEvent, at time: TimeInterval) -> EngineResult {
        switch event {
        case let .keyDown(keyCode, modifiers, isRepeat):
            tapDetector.noteOtherInput()
            recordDetector.noteOtherInput()
            if isRecording {
                return recordKeyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
            }
            // Holding a matched combo auto-repeats: keep eating it, but switch only once.
            if isRepeat, swallowedKeyUps.contains(keyCode) { return .swallowed }

            let match = combos.first {
                $0.combo.keyCode == keyCode && $0.combo.modifiers.matches(modifiers, function: .ignoreUnlessRequired)
            }
            guard let match else {
                // A fresh press means we missed this key's earlier key-up; don't eat the new one.
                if !isRepeat { swallowedKeyUps.remove(keyCode) }
                return .pass
            }
            swallowedKeyUps.insert(keyCode)
            return EngineResult(swallow: true, effect: isRepeat ? nil : .perform(match.action))

        case let .keyUp(keyCode):
            return EngineResult(swallow: swallowedKeyUps.remove(keyCode) != nil)

        case let .modifiersChanged(keys):
            // Both detectors always see modifier changes so their "held" state stays true.
            let chord = tapDetector.modifiersChanged(to: keys, at: time)
            let recordedChord = recordDetector.modifiersChanged(to: keys, at: time)
            if isRecording {
                guard let recordedChord else { return .pass }
                isRecording = false
                return EngineResult(swallow: false, effect: .recorded(.modifierTap(ModifierPattern(exactly: recordedChord))))
            }
            guard let chord, let match = taps.first(where: { $0.pattern.matches(chord, function: .exact) }) else {
                return .pass
            }
            // Never swallow modifier events: apps must always see modifier state change.
            return EngineResult(swallow: false, effect: .perform(match.action))

        case .otherInput:
            tapDetector.noteOtherInput()
            recordDetector.noteOtherInput()
            return .pass
        }
    }

    private mutating func recordKeyDown(keyCode: UInt16, modifiers: ModifierKeys, isRepeat: Bool) -> EngineResult {
        swallowedKeyUps.insert(keyCode)
        if isRepeat { return .swallowed }

        // macOS adds the fn flag to arrows/F-keys by itself; it is never part of a recorded combo.
        let mods = modifiers.withoutFunction
        if mods.isEmpty {
            if keyCode == KeyCode.escape {
                isRecording = false
                return EngineResult(swallow: true, effect: .recordingCancelled)
            }
            // A bare letter as a shortcut would make that letter untypable.
            guard KeyCode.functionKeys.contains(keyCode) else { return .swallowed }
        }
        isRecording = false
        let combo = KeyCombo(keyCode: keyCode, modifiers: ModifierPattern(exactly: mods))
        return EngineResult(swallow: true, effect: .recorded(.keyCombo(combo)))
    }
}
