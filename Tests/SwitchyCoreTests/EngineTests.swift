import Testing
@testable import SwitchyCore

@Suite("Modifier tap detection")
struct ModifierTapDetectorTests {
    @Test func quickTapFires() {
        var d = ModifierTapDetector(maxTapDuration: 0.5)
        #expect(d.modifiersChanged(to: [.rightCommand], at: 0) == nil)
        #expect(d.modifiersChanged(to: [], at: 0.2) == [.rightCommand])
    }

    @Test func holdingTooLongDoesNotFire() {
        var d = ModifierTapDetector(maxTapDuration: 0.5)
        _ = d.modifiersChanged(to: [.rightCommand], at: 0)
        #expect(d.modifiersChanged(to: [], at: 0.8) == nil)
    }

    @Test func anyOtherInputSpoilsTheTap() {
        var d = ModifierTapDetector(maxTapDuration: 0.5)
        _ = d.modifiersChanged(to: [.leftCommand], at: 0)
        d.noteOtherInput() // ⌘C
        #expect(d.modifiersChanged(to: [], at: 0.1) == nil)
        // The next clean tap works again.
        _ = d.modifiersChanged(to: [.leftCommand], at: 1)
        #expect(d.modifiersChanged(to: [], at: 1.1) == [.leftCommand])
    }

    @Test func inputWithNothingHeldIsHarmless() {
        var d = ModifierTapDetector(maxTapDuration: 0.5)
        d.noteOtherInput()
        _ = d.modifiersChanged(to: [.leftShift], at: 0)
        #expect(d.modifiersChanged(to: [], at: 0.1) == [.leftShift])
    }

    @Test func chordCollectsEveryKeyPressedBeforeFullRelease() {
        var d = ModifierTapDetector(maxTapDuration: 0.5)
        _ = d.modifiersChanged(to: [.leftShift], at: 0)
        _ = d.modifiersChanged(to: [.leftShift, .leftOption], at: 0.05)
        #expect(d.modifiersChanged(to: [.leftOption], at: 0.1) == nil)
        #expect(d.modifiersChanged(to: [], at: 0.15) == [.leftShift, .leftOption])
    }

    @Test func emptyToEmptyNeverFires() {
        var d = ModifierTapDetector(maxTapDuration: 0.5)
        #expect(d.modifiersChanged(to: [], at: 0) == nil)
    }

    @Test func resetIgnoresChordAlreadyInProgress() {
        var d = ModifierTapDetector(maxTapDuration: 5)
        _ = d.modifiersChanged(to: [.leftCommand], at: 0)
        d.reset()
        #expect(d.modifiersChanged(to: [], at: 0.1) == nil)
    }
}

@Suite("Shortcut engine")
struct ShortcutEngineTests {
    static let optionOne = ShortcutBinding(
        action: .select(sourceID: "abc"),
        shortcut: .keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .left)))
    )
    static let rightCommandTap = ShortcutBinding(
        action: .select(sourceID: "ukr"),
        shortcut: .modifierTap(ModifierPattern(command: .right))
    )

    func engine(_ bindings: [ShortcutBinding] = [optionOne, rightCommandTap]) -> ShortcutEngine {
        ShortcutEngine(bindings: bindings, maxTapDuration: 0.5)
    }

    @Test func comboFiresAndIsSwallowedIncludingKeyUp() {
        var e = engine()
        _ = e.handle(.modifiersChanged([.rightOption]), at: 0)
        // Recorded with Left ⌥, but key combos match either side by default.
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [.rightOption], isRepeat: false), at: 0.1)
            == EngineResult(swallow: true, effect: .perform(.select(sourceID: "abc"))))
        #expect(e.handle(.keyUp(keyCode: 18), at: 0.2) == .swallowed)
        // The ⌥ press was spoiled by "1", so releasing ⌥ is not a tap.
        #expect(e.handle(.modifiersChanged([]), at: 0.3) == .pass)
    }

    @Test func nonMatchingKeysPassThrough() {
        var e = engine()
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [], isRepeat: false), at: 0) == .pass)
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption, .leftShift], isRepeat: false), at: 0) == .pass)
        #expect(e.handle(.keyUp(keyCode: 18), at: 0.1) == .pass)
    }

    @Test func sideSpecificComboWhenEitherSideIsOff() {
        var binding = Self.optionOne
        binding.matchEitherSide = false
        var e = engine([binding])
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [.rightOption], isRepeat: false), at: 0) == .pass)
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 0).swallow)
    }

    @Test func autoRepeatIsSwallowedButFiresOnce() {
        var e = engine()
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 0).effect != nil)
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: true), at: 0.5) == .swallowed)
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [], isRepeat: true), at: 0.6) == .swallowed)
    }

    @Test func missedKeyUpDoesNotEatTheNextPress() {
        var e = engine()
        _ = e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 0)
        // Key-up lost (e.g. tap briefly disabled). Next plain "1" must type and release normally.
        #expect(e.handle(.keyDown(keyCode: 18, modifiers: [], isRepeat: false), at: 1) == .pass)
        #expect(e.handle(.keyUp(keyCode: 18), at: 1.1) == .pass)
    }

    @Test func arrowKeyComboIgnoresAutomaticFnFlag() {
        let binding = ShortcutBinding(action: .next, shortcut: .keyCombo(KeyCombo(keyCode: 124, modifiers: ModifierPattern(control: .either))))
        var e = engine([binding])
        #expect(e.handle(.keyDown(keyCode: 124, modifiers: [.leftControl, .function], isRepeat: false), at: 0).effect == .perform(.next))
    }

    @Test func modifierTapFiresOnReleaseWithoutSwallowing() {
        var e = engine()
        #expect(e.handle(.modifiersChanged([.rightCommand]), at: 0) == .pass)
        #expect(e.handle(.modifiersChanged([]), at: 0.1) == EngineResult(swallow: false, effect: .perform(.select(sourceID: "ukr"))))
    }

    @Test func modifierTapIsSideAware() {
        var e = engine()
        _ = e.handle(.modifiersChanged([.leftCommand]), at: 0)
        #expect(e.handle(.modifiersChanged([]), at: 0.1) == .pass)
    }

    @Test func commandShortcutsInAppsDoNotTriggerTap() {
        var e = engine()
        _ = e.handle(.modifiersChanged([.rightCommand]), at: 0)
        #expect(e.handle(.keyDown(keyCode: 8, modifiers: [.rightCommand], isRepeat: false), at: 0.05) == .pass) // ⌘C
        _ = e.handle(.keyUp(keyCode: 8), at: 0.07)
        #expect(e.handle(.modifiersChanged([]), at: 0.1) == .pass)
    }

    @Test func commandClickDoesNotTriggerTap() {
        var e = engine()
        _ = e.handle(.modifiersChanged([.rightCommand]), at: 0)
        _ = e.handle(.otherInput, at: 0.05)
        #expect(e.handle(.modifiersChanged([]), at: 0.1) == .pass)
    }

    @Test func tapDurationComesFromConfiguration() {
        var e = engine()
        e.configure(bindings: [Self.rightCommandTap], maxTapDuration: 2)
        _ = e.handle(.modifiersChanged([.rightCommand]), at: 0)
        #expect(e.handle(.modifiersChanged([]), at: 1.5).effect != nil)
    }

    @Test func firstBindingWinsOnOverlap() {
        let a = ShortcutBinding(action: .next, shortcut: .modifierTap(ModifierPattern(command: .either)))
        let b = ShortcutBinding(action: .previous, shortcut: .modifierTap(ModifierPattern(command: .right)))
        var e = engine([a, b])
        _ = e.handle(.modifiersChanged([.rightCommand]), at: 0)
        #expect(e.handle(.modifiersChanged([]), at: 0.1).effect == .perform(.next))
    }

    // MARK: Recording

    @Test func recordsKeyComboAndSwallowsIt() {
        var e = engine()
        e.startRecording()
        _ = e.handle(.modifiersChanged([.leftOption]), at: 0)
        let result = e.handle(.keyDown(keyCode: 10, modifiers: [.leftOption], isRepeat: false), at: 0.1)
        #expect(result == EngineResult(swallow: true, effect: .recorded(.keyCombo(KeyCombo(keyCode: 10, modifiers: ModifierPattern(option: .left))))))
        #expect(!e.isRecording)
        #expect(e.handle(.keyUp(keyCode: 10), at: 0.2) == .swallowed)
    }

    @Test func recordingDoesNotFireExistingShortcuts() {
        var e = engine()
        e.startRecording()
        let result = e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 0)
        #expect(result.effect == .recorded(.keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .left)))))
    }

    @Test func recordsModifierTapWithExactSides() {
        var e = engine()
        e.startRecording()
        _ = e.handle(.modifiersChanged([.rightCommand]), at: 0)
        // Slow on purpose: recording is patient even though normal taps would time out.
        #expect(e.handle(.modifiersChanged([]), at: 2).effect == .recorded(.modifierTap(ModifierPattern(command: .right))))
    }

    @Test func escapeCancelsRecording() {
        var e = engine()
        e.startRecording()
        #expect(e.handle(.keyDown(keyCode: KeyCode.escape, modifiers: [], isRepeat: false), at: 0)
            == EngineResult(swallow: true, effect: .recordingCancelled))
        #expect(!e.isRecording)
    }

    @Test func bareLetterIsRejectedButFunctionKeyAccepted() {
        var e = engine()
        e.startRecording()
        #expect(e.handle(.keyDown(keyCode: 0, modifiers: [], isRepeat: false), at: 0) == .swallowed)
        #expect(e.isRecording)
        // F13 arrives with the automatic fn flag; it must not end up in the shortcut.
        #expect(e.handle(.keyDown(keyCode: 105, modifiers: [.function], isRepeat: false), at: 0.1).effect
            == .recorded(.keyCombo(KeyCombo(keyCode: 105, modifiers: ModifierPattern()))))
    }

    @Test func comboDuringRecordingDoesNotAlsoRecordTheModifierTap() {
        var e = engine()
        e.startRecording()
        _ = e.handle(.modifiersChanged([.leftOption]), at: 0)
        _ = e.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 0.1)
        e.startRecording()
        _ = e.handle(.keyUp(keyCode: 18), at: 0.15)
        #expect(e.handle(.modifiersChanged([]), at: 0.2) == .pass)
        #expect(e.isRecording)
    }
}

@Suite("Layout cycling")
struct LayoutCyclerTests {
    let ids = ["abc", "ukr", "jp"]

    @Test func nextAndPreviousWrapAround() {
        #expect(LayoutCycler.target(for: .next, among: ids, current: "abc") == "ukr")
        #expect(LayoutCycler.target(for: .next, among: ids, current: "jp") == "abc")
        #expect(LayoutCycler.target(for: .previous, among: ids, current: "abc") == "jp")
    }

    @Test func unknownCurrentStartsAtTheEdge() {
        #expect(LayoutCycler.target(for: .next, among: ids, current: "emoji") == "abc")
        #expect(LayoutCycler.target(for: .previous, among: ids, current: nil) == "jp")
    }

    @Test func selectOnlyEnabledSources() {
        #expect(LayoutCycler.target(for: .select(sourceID: "ukr"), among: ids, current: "abc") == "ukr")
        #expect(LayoutCycler.target(for: .select(sourceID: "gone"), among: ids, current: "abc") == nil)
        #expect(LayoutCycler.target(for: .next, among: [], current: nil) == nil)
    }
}
