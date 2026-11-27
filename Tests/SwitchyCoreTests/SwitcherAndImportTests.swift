import Foundation
import Testing
@testable import SwitchyCore

@MainActor
final class FakeBackend: InputSourceBackend {
    var current: String?
    /// Number of select calls the "system" ignores before honouring one.
    var ignoredSelects: Int
    /// Applied current source only becomes visible this many checks after a successful select.
    var visibleAfterChecks = 0
    private(set) var selectCalls: [String] = []
    private var pending: (id: String, checksLeft: Int)?

    init(current: String?, ignoredSelects: Int = 0) {
        self.current = current
        self.ignoredSelects = ignoredSelects
    }

    func currentSourceID() -> String? {
        if var p = pending {
            if p.checksLeft == 0 {
                current = p.id
                pending = nil
            } else {
                p.checksLeft -= 1
                pending = p
            }
        }
        return current
    }

    func selectSource(id: String) -> Bool {
        selectCalls.append(id)
        if ignoredSelects > 0 {
            ignoredSelects -= 1
            return true
        }
        if visibleAfterChecks > 0 {
            pending = (id, visibleAfterChecks)
        } else {
            current = id
        }
        return true
    }
}

/// Runs scheduled retries later, on demand, so tests control time.
@MainActor
final class ManualScheduler {
    var queue: [(TimeInterval, InputSourceSwitcher.Work)] = []
    func schedule(_ delay: TimeInterval, _ work: @escaping InputSourceSwitcher.Work) { queue.append((delay, work)) }
    func runAll() {
        while !queue.isEmpty { queue.removeFirst().1() }
    }
}

@Suite("Input source switching")
@MainActor
struct InputSourceSwitcherTests {
    func make(_ backend: FakeBackend, _ scheduler: ManualScheduler) -> InputSourceSwitcher {
        InputSourceSwitcher(backend: backend, retryDelays: [0.03, 0.08, 0.2], schedule: scheduler.schedule)
    }

    @Test func succeedsFirstTime() {
        let backend = FakeBackend(current: "abc")
        let scheduler = ManualScheduler()
        var outcome: SwitchOutcome?
        make(backend, scheduler).switchTo("ukr") { outcome = $0 }
        #expect(outcome == SwitchOutcome(targetID: "ukr", attempts: 1, succeeded: true))
        #expect(scheduler.queue.isEmpty)
    }

    @Test func retriesWhenTheSystemDropsTheRequest() {
        let backend = FakeBackend(current: "abc", ignoredSelects: 2)
        let scheduler = ManualScheduler()
        var outcome: SwitchOutcome?
        let switcher = make(backend, scheduler) // retries hold the switcher weakly
        switcher.switchTo("ukr") { outcome = $0 }
        #expect(outcome == nil)
        scheduler.runAll()
        #expect(outcome == SwitchOutcome(targetID: "ukr", attempts: 3, succeeded: true))
        #expect(backend.selectCalls == ["ukr", "ukr", "ukr"])
    }

    @Test func lateButSuccessfulSwitchIsNotSelectedAgain() {
        let backend = FakeBackend(current: "abc")
        backend.visibleAfterChecks = 1
        let scheduler = ManualScheduler()
        var outcome: SwitchOutcome?
        let switcher = make(backend, scheduler)
        switcher.switchTo("ukr") { outcome = $0 }
        scheduler.runAll()
        #expect(outcome == SwitchOutcome(targetID: "ukr", attempts: 1, succeeded: true))
        #expect(backend.selectCalls == ["ukr"])
    }

    @Test func givesUpAfterAllRetries() {
        let backend = FakeBackend(current: "abc", ignoredSelects: 100)
        let scheduler = ManualScheduler()
        var outcome: SwitchOutcome?
        let switcher = make(backend, scheduler)
        switcher.switchTo("ukr") { outcome = $0 }
        scheduler.runAll()
        #expect(outcome == SwitchOutcome(targetID: "ukr", attempts: 4, succeeded: false))
        #expect(switcher.pendingTargetID == nil)
    }

    @Test func alreadyCurrentDoesNothing() {
        let backend = FakeBackend(current: "ukr")
        var outcome: SwitchOutcome?
        make(backend, ManualScheduler()).switchTo("ukr") { outcome = $0 }
        #expect(outcome == SwitchOutcome(targetID: "ukr", attempts: 0, succeeded: true))
        #expect(backend.selectCalls.isEmpty)
    }

    @Test func newerRequestSupersedesPendingRetries() {
        let backend = FakeBackend(current: "abc", ignoredSelects: 1)
        let scheduler = ManualScheduler()
        var first: SwitchOutcome?
        var second: SwitchOutcome?
        let switcher = make(backend, scheduler)
        switcher.switchTo("ukr") { first = $0 }
        #expect(switcher.pendingTargetID == "ukr")
        #expect(switcher.effectiveCurrentID == "ukr")
        switcher.switchTo("jp") { second = $0 }
        scheduler.runAll()
        #expect(first == nil)
        #expect(second == SwitchOutcome(targetID: "jp", attempts: 1, succeeded: true))
        #expect(backend.current == "jp")
    }
}

@Suite("MLSwitcher2 import")
struct MLSwitcherImporterTests {
    @Test func decodesTheUsersActualValues() {
        // Taken from this Mac's com.bluezbox.MLSwitcher2 preferences.
        #expect(MLSwitcherImporter.decodeShortcut(524_306)?.displayString == "⌥1")
        #expect(MLSwitcherImporter.decodeShortcut(524_298)?.displayString == "⌥§")
    }

    @Test func decodesEveryModifier() {
        let value = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | 40
        #expect(MLSwitcherImporter.decodeShortcut(value)?.displayString == "⌃⌥⇧⌘K")
        #expect(MLSwitcherImporter.decodeShortcut((1 << 23) | (1 << 17) | 18)?.displayString == "fn + ⇧ + 1")
    }

    @Test(arguments: [0, -1, 18, 1 << 16 | 18, (1 << 19) | 0x1FF])
    func rejectsUnsetOrInvalidValues(_ value: Int) {
        #expect(MLSwitcherImporter.decodeShortcut(value) == nil)
    }

    @Test func importsOnlyEnabledLayoutsAndSkipsSettings() {
        let prefs: [String: Any] = [
            "CycleComboIndex": 0,
            "ShowStatusItem": 1,
            "com.apple.keylayout.ABC": 524_306,
            "com.apple.keylayout.Ukrainian-PC": 524_298,
            "com.apple.keylayout.German": 524_307,
        ]
        let enabled: Set = ["com.apple.keylayout.ABC", "com.apple.keylayout.Ukrainian-PC"]
        let result = MLSwitcherImporter.bindings(from: prefs, enabledSourceIDs: enabled)
        #expect(result.map(\.action) == [.select(sourceID: "com.apple.keylayout.ABC"), .select(sourceID: "com.apple.keylayout.Ukrainian-PC")])
        #expect(result.map(\.effectiveShortcut.displayString) == ["⌥1", "⌥§"])
    }
}

@Suite("Bindings")
struct BindingListTests {
    @Test func defaultsDependOnShortcutKind() {
        let combo = ShortcutBinding(action: .next, shortcut: .keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .left))))
        let tap = ShortcutBinding(action: .next, shortcut: .modifierTap(ModifierPattern(command: .right)))
        #expect(combo.matchEitherSide)
        #expect(combo.effectiveShortcut.displayString == "⌥1")
        #expect(!tap.matchEitherSide)
        #expect(tap.effectiveShortcut.displayString == "Right ⌘")
    }

    @Test func togglingSidesIsLossless() {
        var tap = ShortcutBinding(action: .next, shortcut: .modifierTap(ModifierPattern(command: .right)))
        tap.matchEitherSide = true
        #expect(tap.effectiveShortcut.displayString == "⌘")
        tap.matchEitherSide = false
        #expect(tap.effectiveShortcut.displayString == "Right ⌘")
    }

    @Test func conflictsAreReportedForBothBindings() {
        let a = ShortcutBinding(action: .next, shortcut: .modifierTap(ModifierPattern(command: .either)), matchEitherSide: false)
        let b = ShortcutBinding(action: .previous, shortcut: .modifierTap(ModifierPattern(command: .right)))
        let c = ShortcutBinding(action: .previous, shortcut: .modifierTap(ModifierPattern(shift: .left)))
        #expect(BindingList.conflictingIDs([a, b, c]) == [a.id, b.id])
        #expect(BindingList.conflictingIDs([b, c]).isEmpty)
    }

    @Test func leftAndRightVariantsDoNotConflict() {
        let left = ShortcutBinding(action: .select(sourceID: "abc"), shortcut: .modifierTap(ModifierPattern(command: .left)))
        let right = ShortcutBinding(action: .select(sourceID: "ukr"), shortcut: .modifierTap(ModifierPattern(command: .right)))
        #expect(BindingList.conflictingIDs([left, right]).isEmpty)
    }

    @Test func persistenceRoundTrip() throws {
        let bindings = [
            ShortcutBinding(action: .select(sourceID: "com.apple.keylayout.ABC"), shortcut: .keyCombo(KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .left)))),
            ShortcutBinding(action: .previous, shortcut: .modifierTap(ModifierPattern(exactly: [.leftShift, .leftOption]))),
        ]
        #expect(BindingList.decode(try BindingList.encode(bindings)) == bindings)
    }

    @Test func corruptDataDecodesToEmpty() {
        #expect(BindingList.decode(Data("nope".utf8)).isEmpty)
        #expect(BindingList.decode(nil).isEmpty)
    }

    static let optionOne = KeyCombo(keyCode: 18, modifiers: ModifierPattern(option: .either))

    @Test func shortcutsForRemovedLayoutsAreInactiveButKept() {
        let abc = ShortcutBinding(action: .select(sourceID: "abc"), shortcut: .keyCombo(KeyCombo(keyCode: 29, modifiers: ModifierPattern(option: .either))))
        let ukr = ShortcutBinding(action: .select(sourceID: "ukr"), shortcut: .keyCombo(Self.optionOne))
        let next = ShortcutBinding(action: .next, shortcut: .modifierTap(ModifierPattern(command: .right)))
        let saved = [abc, ukr, next]
        #expect(BindingList.active(saved, enabledSourceIDs: ["abc"]) == [abc, next])
        #expect(BindingList.active(saved, enabledSourceIDs: ["abc", "ukr"]) == saved)
        #expect(BindingList.active(saved, enabledSourceIDs: []) == [next])
    }

    @Test func removedLayoutsShortcutReachesTheApp() {
        let ukr = ShortcutBinding(action: .select(sourceID: "ukr"), shortcut: .keyCombo(Self.optionOne))
        var engine = ShortcutEngine(bindings: BindingList.active([ukr], enabledSourceIDs: ["abc"]))
        #expect(engine.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 0) == .pass)
        engine.configure(bindings: BindingList.active([ukr], enabledSourceIDs: ["abc", "ukr"]), maxTapDuration: ShortcutEngine.defaultMaxTapDuration)
        #expect(engine.handle(.keyDown(keyCode: 18, modifiers: [.leftOption], isRepeat: false), at: 1).effect == .perform(.select(sourceID: "ukr")))
    }

    @Test func inactiveShortcutDoesNotConflictWithALiveOne() {
        let removed = ShortcutBinding(action: .select(sourceID: "ukr"), shortcut: .keyCombo(Self.optionOne))
        let live = ShortcutBinding(action: .select(sourceID: "abc"), shortcut: .keyCombo(Self.optionOne))
        #expect(BindingList.conflictingIDs(BindingList.active([removed, live], enabledSourceIDs: ["abc"])).isEmpty)
        #expect(BindingList.conflictingIDs(BindingList.active([removed, live], enabledSourceIDs: ["abc", "ukr"])) == [removed.id, live.id])
    }

    @Test func stoppingTheTapEndsRecording() {
        // Never started, so no system tap is created; stop() must still clear the engine state.
        let tap = KeyboardEventTap { _ in }
        tap.startRecording()
        #expect(tap.isRecording)
        tap.stop()
        #expect(!tap.isRecording)
    }

    @Test func menuBarLabels() {
        #expect(InputSourceInfo(id: "a", name: "ABC", languageCode: "en", iconURL: nil).shortLabel == "EN")
        #expect(InputSourceInfo(id: "u", name: "Ukrainian – PC", languageCode: "uk", iconURL: nil).shortLabel == "UA")
        #expect(InputSourceInfo(id: "x", name: "Custom", languageCode: nil, iconURL: nil).shortLabel == "CU")
    }
}

@Suite("Menu bar")
struct MenuBarPolicyTests {
    @Test(arguments: [
        (true, true, true, true),     // user wants it
        (false, true, true, false),   // hidden and everything works
        (false, false, false, true),  // no permission: comes back to warn
        (false, true, false, true),   // monitoring refused: comes back to warn
    ])
    func statusItemVisibility(userWantsIt: Bool, granted: Bool, monitoring: Bool, expected: Bool) {
        #expect(MenuBarPolicy.showsStatusItem(userWantsIt: userWantsIt, accessibilityGranted: granted, monitoring: monitoring) == expected)
    }
}

@Suite("Flags")
struct FlagTests {
    @Test func emojiFromRegionCode() {
        #expect(FlagEmoji.emoji(forRegion: "UA") == "🇺🇦")
        #expect(FlagEmoji.emoji(forRegion: "gb") == "🇬🇧")
    }

    @Test(arguments: ["", "U", "UAA", "419", "U1", "Ü1"])
    func rejectsNonRegionCodes(_ code: String) {
        #expect(FlagEmoji.emoji(forRegion: code) == nil)
    }

    @Test func automaticRegionForThisMacsLayouts() {
        #expect(FlagEmoji.automaticRegion(sourceID: "com.apple.keylayout.Ukrainian-PC", languageCode: "uk") == "UA")
        #expect(FlagEmoji.automaticRegion(sourceID: "com.apple.keylayout.ABC", languageCode: "en") == "US")
    }

    @Test func layoutNameBeatsLanguage() {
        #expect(FlagEmoji.automaticRegion(sourceID: "com.apple.keylayout.British", languageCode: "en") == "GB")
        #expect(FlagEmoji.automaticRegion(sourceID: "com.apple.keylayout.SwissGerman", languageCode: "de") == "CH")
    }

    @Test func languageWithScriptOrRegion() {
        #expect(FlagEmoji.automaticRegion(sourceID: "com.apple.inputmethod.SCIM.ITABC", languageCode: "zh-Hans") == "CN")
        #expect(FlagEmoji.automaticRegion(sourceID: "x.y.Portuguese", languageCode: "pt-BR") == "BR")
    }

    @Test func noLanguageMeansNoFlag() {
        #expect(FlagEmoji.automaticRegion(sourceID: "com.example.Custom", languageCode: nil) == nil)
        // Latin America (419) has no flag.
        #expect(FlagEmoji.automaticRegion(sourceID: "x.y.LatinAmerican", languageCode: "es-419") == nil)
    }

    @Test func regionListIsSortedAndFlaggable() {
        let regions = FlagEmoji.allRegions(locale: Locale(identifier: "en_US"))
        #expect(regions.count > 200)
        #expect(regions.contains { $0.code == "UA" && $0.name == "Ukraine" && $0.emoji == "🇺🇦" })
        #expect(regions.allSatisfy { $0.code.count == 2 })
        let names = regions.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }
}

@Suite("Flag wave")
struct FlagWaveTests {
    let wave = FlagWave(amplitude: 2, wavelength: 30, shade: 0.2)

    @Test func poleEdgeNeverMoves() {
        for frame in FlagWave.loop(frameCount: 12) {
            #expect(wave.offset(column: 0, width: 32, frame: frame) == 0)
            #expect(wave.shading(column: 0, width: 32, frame: frame) == 0)
        }
    }

    @Test func staysWithinAmplitudeAndShade() {
        for frame in FlagWave.loop(frameCount: 24) + FlagWave.burst(frameCount: 24, cycles: 1.5) {
            for x in stride(from: 0.0, through: 32, by: 0.5) {
                #expect(abs(wave.offset(column: x, width: 32, frame: frame)) <= 2 + 1e-9)
                #expect(abs(wave.shading(column: x, width: 32, frame: frame)) <= 0.2 + 1e-9)
            }
        }
    }

    @Test func flatFrameIsFlat() {
        for x in stride(from: 0.0, through: 32, by: 1) {
            #expect(wave.offset(column: x, width: 32, frame: .flat) == 0)
        }
    }

    @Test func loopActuallyMovesAndWrapsAround() {
        let frames = FlagWave.loop(frameCount: 30)
        #expect(frames.count == 30)
        #expect(frames.allSatisfy { $0.strength == 1 })
        #expect(wave.offset(column: 24, width: 32, frame: frames[0]) != wave.offset(column: 24, width: 32, frame: frames[7]))
        // One step past the last frame is a full turn: back to the first, so there's no hitch.
        let step = frames[1].phase - frames[0].phase
        #expect(abs(frames[29].phase + step - 2 * .pi) < 1e-9)
    }

    @Test func burstStartsAndEndsFlat() {
        let frames = FlagWave.burst(frameCount: 30, cycles: 1.5)
        #expect(frames.first?.strength == 0)
        #expect(frames.last?.strength == 0)
        #expect(frames.map(\.strength).max()! > 0.99)
        #expect(abs(frames.last!.phase - 3 * .pi) < 1e-9)
        #expect(FlagWave.burst(frameCount: 1, cycles: 1) == [.flat])
        #expect(FlagWave.burst(frameCount: 0, cycles: 1).isEmpty)
    }

    @Test func alphaBoundsFindsOpaqueBox() {
        // 4×3 RGBA, opaque pixels at (1,1) and (2,2).
        var pixels = [UInt8](repeating: 0, count: 4 * 3 * 4)
        pixels[(1 * 4 + 1) * 4 + 3] = 255
        pixels[(2 * 4 + 2) * 4 + 3] = 200
        let rect = pixels.withUnsafeBufferPointer { AlphaBounds.find(in: $0, width: 4, height: 3, bytesPerRow: 16) }
        #expect(rect == PixelRect(x: 1, y: 1, width: 2, height: 2))
        let empty = [UInt8](repeating: 0, count: 16)
        #expect(empty.withUnsafeBufferPointer { AlphaBounds.find(in: $0, width: 2, height: 2, bytesPerRow: 8) } == nil)
    }
}
