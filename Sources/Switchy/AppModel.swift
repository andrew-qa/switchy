import AppKit
import Carbon
import Observation
import ServiceManagement
import SwitchyCore
import os

enum MenuBarStyle: String, CaseIterable {
    case languageCode
    case flag
}

enum FlagAnimation: String, CaseIterable {
    case off
    case onSwitch
    case always
}

struct SwitchStats {
    var switches = 0
    var retried = 0
    var failed = 0
    var tapReenabled = 0
}

/// All app state, on the main actor. The event tap thread talks to it only through `handle(_:)`.
@MainActor
@Observable
final class AppModel {
    private(set) var sources: [InputSourceInfo] = []
    private(set) var currentSourceID: String?
    private(set) var bindings: [ShortcutBinding] = []
    private(set) var recordingFor: SwitchAction?
    private(set) var accessibilityGranted = false
    private(set) var tapRunning = false
    private(set) var secureInputActive = false
    private(set) var secureInputOwner: String?
    private(set) var mlSwitcherRunning = false
    private(set) var mlSwitcherHasSettings = false
    private(set) var maxTapDuration: TimeInterval
    private(set) var hideSystemIndicator = SystemInputIndicator.isHidden
    private(set) var indicatorChangePending = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?
    private(set) var stats = SwitchStats()
    private(set) var lastImportCount: Int?
    private(set) var showStatusItem: Bool
    private(set) var systemInputMenuVisible = SystemInputMenu.isVisible
    private(set) var menuBarStyle: MenuBarStyle
    /// Input source ID → region code, for layouts whose automatic flag isn't the one you want.
    private(set) var flagOverrides: [String: String]
    private(set) var flagAnimation: FlagAnimation
    private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Called whenever something the menu bar shows may have changed.
    @ObservationIgnored var onDisplayChange: (() -> Void)?

    @ObservationIgnored private var tap: KeyboardEventTap?
    @ObservationIgnored private let switcher = InputSourceSwitcher(backend: TISInputSourceBackend())
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var cachedFlagRegions: [FlagRegion]?
    @ObservationIgnored private let flagArtCache = FlagArtCache()
    @ObservationIgnored private let log = Logger(subsystem: "Switchy", category: "App")

    private enum Keys {
        static let bindings = "bindings"
        static let maxTapDuration = "maxTapDuration"
        static let didLaunchBefore = "didLaunchBefore"
        static let showStatusItem = "showStatusItem"
        static let menuBarStyle = "menuBarStyle"
        static let flagOverrides = "flagOverrides"
        static let flagAnimation = "flagAnimation"
    }

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.maxTapDuration)
        maxTapDuration = stored > 0 ? stored : ShortcutEngine.defaultMaxTapDuration
        bindings = BindingList.decode(defaults.data(forKey: Keys.bindings))
        showStatusItem = UserDefaults.standard.object(forKey: Keys.showStatusItem) as? Bool ?? true
        menuBarStyle = UserDefaults.standard.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .languageCode
        flagOverrides = UserDefaults.standard.dictionary(forKey: Keys.flagOverrides) as? [String: String] ?? [:]
        flagAnimation = UserDefaults.standard.string(forKey: Keys.flagAnimation).flatMap(FlagAnimation.init) ?? .onSwitch
    }

    var isFirstLaunch: Bool { !defaults.bool(forKey: Keys.didLaunchBefore) }

    func start() {
        let firstLaunch = isFirstLaunch
        tap = KeyboardEventTap { [weak self] effect in
            Task { @MainActor in self?.handle(effect) }
        }
        reloadSources()
        mlSwitcherHasSettings = MLSwitcherImporter.readPreferences() != nil
        if firstLaunch && bindings.isEmpty {
            importFromMLSwitcher()
        }
        defaults.set(true, forKey: Keys.didLaunchBefore)
        pushConfiguration()
        observeSystem()
        refreshPermissionAndTap(prompt: true)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: Derived

    var currentSource: InputSourceInfo? { sources.first { $0.id == currentSourceID } }
    var statusItemVisible: Bool {
        MenuBarPolicy.showsStatusItem(userWantsIt: showStatusItem, accessibilityGranted: accessibilityGranted, monitoring: tapRunning)
    }
    var conflicts: Set<UUID> { BindingList.conflictingIDs(bindings) }

    func bindings(for action: SwitchAction) -> [ShortcutBinding] {
        bindings.filter { $0.action == action }
    }

    func title(for action: SwitchAction) -> String {
        switch action {
        case .select(let id): sources.first { $0.id == id }?.name ?? id
        case .next: "Next layout"
        case .previous: "Previous layout"
        }
    }

    func automaticFlagRegion(for source: InputSourceInfo) -> String? {
        FlagEmoji.automaticRegion(sourceID: source.id, languageCode: source.languageCode)
    }

    func flag(for source: InputSourceInfo) -> String? {
        (flagOverrides[source.id] ?? automaticFlagRegion(for: source)).flatMap(FlagEmoji.emoji(forRegion:))
    }

    /// What represents a layout in the menu bar and menus: its flag, or "EN"/"UA".
    func badge(for source: InputSourceInfo) -> String {
        if menuBarStyle == .flag, let flag = flag(for: source) { return flag }
        return source.shortLabel
    }

    /// What actually plays: macOS's Reduce Motion setting overrides the user's choice.
    var effectiveFlagAnimation: FlagAnimation { reduceMotion ? .off : flagAnimation }

    func flagArt(for emoji: String) -> FlagArt? {
        flagArtCache.art(for: emoji)
    }

    func flagRegions() -> [FlagRegion] {
        if let cachedFlagRegions { return cachedFlagRegions }
        let regions = FlagEmoji.allRegions()
        cachedFlagRegions = regions
        return regions
    }

    func icon(for source: InputSourceInfo) -> NSImage? {
        if let cached = iconCache[source.id] { return cached }
        guard let url = source.iconURL, let image = NSImage(contentsOf: url) else { return nil }
        iconCache[source.id] = image
        return image
    }

    // MARK: Switching

    func perform(_ action: SwitchAction) {
        let ids = sources.map(\.id)
        guard let target = LayoutCycler.target(for: action, among: ids, current: switcher.effectiveCurrentID) else {
            log.notice("Nothing to switch to for \(String(describing: action), privacy: .public)")
            return
        }
        switcher.switchTo(target) { [weak self] outcome in
            self?.record(outcome)
        }
    }

    private func record(_ outcome: SwitchOutcome) {
        if outcome.attempts > 0 { stats.switches += 1 }
        if outcome.attempts > 1 { stats.retried += 1 }
        if !outcome.succeeded {
            stats.failed += 1
            log.error("Switch to \(outcome.targetID, privacy: .public) failed after \(outcome.attempts) attempts")
        } else if outcome.attempts > 1 {
            log.notice("Switch to \(outcome.targetID, privacy: .public) needed \(outcome.attempts) attempts")
        }
        updateCurrentSource()
    }

    private func handle(_ effect: EngineEffect) {
        switch effect {
        case .perform(let action):
            perform(action)
        case .recorded(let shortcut):
            guard let action = recordingFor else { return }
            recordingFor = nil
            setBindings(bindings + [ShortcutBinding(action: action, shortcut: shortcut)])
        case .recordingCancelled:
            recordingFor = nil
        }
    }

    // MARK: Editing shortcuts

    func startRecording(for action: SwitchAction) {
        guard tapRunning else { return }
        recordingFor = action
        tap?.startRecording()
    }

    func cancelRecording() {
        guard recordingFor != nil else { return }
        recordingFor = nil
        tap?.cancelRecording()
    }

    func removeBinding(_ id: UUID) {
        setBindings(bindings.filter { $0.id != id })
    }

    func setMatchEitherSide(_ value: Bool, for id: UUID) {
        setBindings(bindings.map { binding in
            var binding = binding
            if binding.id == id { binding.matchEitherSide = value }
            return binding
        })
    }

    func setMaxTapDuration(_ value: TimeInterval) {
        maxTapDuration = value
        defaults.set(value, forKey: Keys.maxTapDuration)
        pushConfiguration()
    }

    private func setBindings(_ new: [ShortcutBinding]) {
        bindings = new
        do {
            defaults.set(try BindingList.encode(new), forKey: Keys.bindings)
        } catch {
            log.error("Could not save shortcuts: \(error.localizedDescription, privacy: .public)")
        }
        pushConfiguration()
        onDisplayChange?()
    }

    private func pushConfiguration() {
        tap?.configure(bindings: bindings, maxTapDuration: maxTapDuration)
    }

    // MARK: MLSwitcher2

    /// Adds MLSwitcher2's shortcuts that aren't already set up here. Returns how many were added.
    @discardableResult
    func importFromMLSwitcher() -> Int {
        guard let prefs = MLSwitcherImporter.readPreferences() else {
            lastImportCount = 0
            return 0
        }
        let imported = MLSwitcherImporter.bindings(from: prefs, enabledSourceIDs: Set(sources.map(\.id)))
        let fresh = imported.filter { candidate in
            !bindings.contains { $0.action == candidate.action && $0.effectiveShortcut == candidate.effectiveShortcut }
        }
        if !fresh.isEmpty { setBindings(bindings + fresh) }
        lastImportCount = fresh.count
        return fresh.count
    }

    func quitMLSwitcher() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: MLSwitcherImporter.bundleID) {
            app.terminate()
        }
    }

    // MARK: Options

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setHideSystemIndicator(_ hidden: Bool) {
        SystemInputIndicator.setHidden(hidden)
        let now = SystemInputIndicator.isHidden
        if now != hideSystemIndicator { indicatorChangePending.toggle() }
        hideSystemIndicator = now
    }

    func setShowStatusItem(_ show: Bool) {
        showStatusItem = show
        defaults.set(show, forKey: Keys.showStatusItem)
        onDisplayChange?()
    }

    func setMenuBarStyle(_ style: MenuBarStyle) {
        menuBarStyle = style
        defaults.set(style.rawValue, forKey: Keys.menuBarStyle)
        onDisplayChange?()
    }

    func setFlagAnimation(_ animation: FlagAnimation) {
        flagAnimation = animation
        defaults.set(animation.rawValue, forKey: Keys.flagAnimation)
        onDisplayChange?()
    }

    /// nil goes back to the automatic flag.
    func setFlagOverride(_ region: String?, for sourceID: String) {
        flagOverrides[sourceID] = region
        defaults.set(flagOverrides, forKey: Keys.flagOverrides)
        onDisplayChange?()
    }

    func setSystemInputMenuVisible(_ visible: Bool) {
        SystemInputMenu.setVisible(visible)
        systemInputMenuVisible = SystemInputMenu.isVisible
    }

    // MARK: System state

    func refreshPermissionAndTap(prompt: Bool = false) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        guard let tap else { return }

        if accessibilityGranted && !tap.isRunning {
            if tap.start() {
                log.info("Keyboard monitoring started")
            } else {
                // Accessibility is on but macOS still refused: ask for Input Monitoring as well.
                _ = CGRequestListenEventAccess()
            }
        } else if !accessibilityGranted && tap.isRunning {
            tap.stop()
        }
        if tap.ensureEnabled() { stats.tapReenabled += 1 }
        tapRunning = tap.isRunning
        if !tapRunning { recordingFor = nil }
        onDisplayChange?()
    }

    private func tick() {
        refreshPermissionAndTap()
        secureInputActive = SecureInput.isActive
        secureInputOwner = secureInputActive
            ? SecureInput.ownerPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            : nil
        // Picks up changes made in System Settings too.
        systemInputMenuVisible = SystemInputMenu.isVisible
        mlSwitcherRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: MLSwitcherImporter.bundleID).isEmpty
        updateCurrentSource()
    }

    private func reloadSources() {
        sources = InputSourceCatalog.enabledKeyboardSources()
        iconCache = [:]
        updateCurrentSource()
    }

    private func updateCurrentSource() {
        let id = TISInputSourceBackend().currentSourceID()
        if id != currentSourceID {
            currentSourceID = id
        }
        onDisplayChange?()
    }

    private func restartTap() {
        guard let tap else { return }
        tap.stop()
        tapRunning = false
        refreshPermissionAndTap()
    }

    private func observeSystem() {
        let distributed = DistributedNotificationCenter.default()
        let selectedChanged = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        let enabledChanged = Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
        observers.append(distributed.addObserver(forName: selectedChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCurrentSource() }
        })
        observers.append(distributed.addObserver(forName: enabledChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSources() }
        })
        // After sleep the window server may have dropped the tap; rebuild it from scratch.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self?.onDisplayChange?()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartTap()
                self?.reloadSources()
            }
        })
    }
}
