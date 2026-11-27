import Testing
@testable import SwitchyCore

@Suite("Decoding event flags")
struct ModifierKeysDecodingTests {
    @Test func tellsLeftAndRightCommandApart() {
        #expect(ModifierKeys(eventFlags: 0x10_0000 | 0x08) == [.leftCommand])
        #expect(ModifierKeys(eventFlags: 0x10_0000 | 0x10) == [.rightCommand])
        #expect(ModifierKeys(eventFlags: 0x10_0000 | 0x18) == [.leftCommand, .rightCommand])
    }

    @Test func realRightOptionEventIncludingNonCoalescedBit() {
        // What macOS actually sends while Right ⌥ is held: 0x80000 | NX_DEVICERALTKEYMASK | 0x100.
        #expect(ModifierKeys(eventFlags: 0x8_0140) == [.rightOption])
    }

    @Test func missingSideBitsFallBackToLeft() {
        #expect(ModifierKeys(eventFlags: 0x8_0000) == [.leftOption])
    }

    @Test func staleSideBitsWithoutTheModifierAreIgnored() {
        #expect(ModifierKeys(eventFlags: 0x08) == [])
    }

    @Test func capsLockAndNumericPadAreNotModifiers() {
        #expect(ModifierKeys(eventFlags: 0x1_0000 | 0x20_0000) == [])
    }

    @Test func functionKey() {
        #expect(ModifierKeys(eventFlags: 0x80_0000) == [.function])
    }

    @Test func roundTripsEveryCombination() {
        for raw in 0..<UInt16(1 << 9) {
            let keys = ModifierKeys(rawValue: raw)
            #expect(ModifierKeys(eventFlags: EventFlagLayout.eventFlags(for: keys)) == keys)
        }
    }
}

@Suite("Modifier patterns")
struct ModifierPatternTests {
    @Test(arguments: [
        (SideRequirement.none, false, false, true), (.none, true, false, false),
        (.either, true, false, true), (.either, false, true, true), (.either, false, false, false),
        (.left, true, false, true), (.left, true, true, false), (.left, false, true, false),
        (.right, false, true, true), (.right, true, true, false),
        (.both, true, true, true), (.both, true, false, false),
    ])
    func sideRequirement(_ req: SideRequirement, left: Bool, right: Bool, expected: Bool) {
        #expect(req.isSatisfied(left: left, right: right) == expected)
    }

    @Test func exactPatternMatchesOnlyThoseKeys() {
        let pattern = ModifierPattern(exactly: [.rightCommand])
        #expect(pattern.command == .right)
        #expect(pattern.matches([.rightCommand]))
        #expect(!pattern.matches([.leftCommand]))
        #expect(!pattern.matches([.rightCommand, .leftShift]))
        #expect(!pattern.matches([.rightCommand, .function]))
    }

    @Test func eitherSideLoosensSidesOnly() {
        let pattern = ModifierPattern(exactly: [.leftShift, .rightOption]).eitherSide
        #expect(pattern == ModifierPattern(option: .either, shift: .either))
        #expect(pattern.matches([.rightShift, .leftOption]))
        #expect(!pattern.matches([.rightShift]))
    }

    @Test func functionPolicyForKeyCombos() {
        let option = ModifierPattern(option: .either)
        // Arrow keys arrive with fn set automatically; ⌥← must still match.
        #expect(option.matches([.leftOption, .function], function: .ignoreUnlessRequired))
        #expect(!option.matches([.leftOption, .function], function: .exact))
        let fnOption = ModifierPattern(option: .either, function: true)
        #expect(!fnOption.matches([.leftOption], function: .ignoreUnlessRequired))
    }

    @Test func overlapDetection() {
        let either = ModifierPattern(command: .either)
        let left = ModifierPattern(command: .left)
        let right = ModifierPattern(command: .right)
        #expect(either.overlaps(left))
        #expect(left.overlaps(either))
        #expect(!left.overlaps(right))
        #expect(!ModifierPattern(command: .both).overlaps(left))
        #expect(!either.overlaps(ModifierPattern(command: .either, function: true), function: .exact))
        #expect(either.overlaps(ModifierPattern(command: .either, function: true), function: .ignoreUnlessRequired))
    }

    @Test func displayStrings() {
        #expect(ModifierPattern(control: .either, option: .either, shift: .either, command: .either).displayString == "⌃⌥⇧⌘")
        #expect(ModifierPattern(command: .right).displayString == "Right ⌘")
        #expect(ModifierPattern(exactly: [.leftShift, .leftOption]).displayString == "Left ⌥ + Left ⇧")
        #expect(ModifierPattern(shift: .either, function: true).displayString == "fn + ⇧")
    }
}

@Suite("Shortcuts")
struct ShortcutTests {
    @Test func keyComboDisplay() {
        #expect(Shortcut.keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .either))).displayString == "⌥1")
        #expect(Shortcut.keyCombo(KeyCombo(keyCode: 10, modifiers: ModifierPattern(option: .either))).displayString == "⌥§")
        #expect(Shortcut.keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .right))).displayString == "Right ⌥ + 1")
        #expect(Shortcut.keyCombo(KeyCombo(keyCode: 105, modifiers: ModifierPattern())).displayString == "F13")
        #expect(Shortcut.modifierTap(ModifierPattern(command: .right)).displayString == "Right ⌘")
    }

    @Test func keyNames() {
        #expect(KeyCode.name(for: 49) == "Space")
        #expect(KeyCode.name(for: 122) == "F1")
        #expect(KeyCode.name(for: 200) == "Key 200")
    }

    @Test func overlapRequiresSameKindAndKey() {
        let optOne = Shortcut.keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .either)))
        let rightOptOne = Shortcut.keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .right)))
        let optTwo = Shortcut.keyCombo(KeyCombo(keyCode: 19, modifiers: ModifierPattern(option: .either)))
        let optTap = Shortcut.modifierTap(ModifierPattern(option: .either))
        #expect(optOne.overlaps(rightOptOne))
        #expect(!optOne.overlaps(optTwo))
        #expect(!optOne.overlaps(optTap))
    }

    @Test func eitherSideOnComboAndTap() {
        let combo = Shortcut.keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .left)))
        #expect(combo.isSideSpecific)
        #expect(!combo.eitherSide.isSideSpecific)
        #expect(Shortcut.modifierTap(ModifierPattern(command: .right)).eitherSide == .modifierTap(ModifierPattern(command: .either)))
    }
}
