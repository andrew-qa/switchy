import AppKit
import SwitchyCore

/// The menu bar item: current layout label, plus a menu to switch, see problems, and open settings.
/// It deliberately shows no hover tooltip and no popups.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let openSettings: () -> Void
    private let player = FlagPlayer()
    private var observers: [NSObjectProtocol] = []
    private var screensAsleep = false
    private var shownSourceID: String?
    private var shownFlag: String?

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        player.show = { [weak self] image in self?.item.button?.image = image }
        model.onDisplayChange = { [weak self] in self?.refreshButton() }

        // Never animate for a dark screen.
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = true
                self?.refreshButton()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = false
                self?.refreshButton()
            }
        })
        refreshButton()
    }

    /// Called on every model change and every 2 s, so it must be idempotent: it only starts an
    /// animation when the layout or flag actually changed, and never restarts a running one.
    func refreshButton() {
        guard let button = item.button else { return }
        button.appearsDisabled = !(model.tapRunning && !model.secureInputActive)
        button.toolTip = nil
        item.isVisible = model.statusItemVisible

        let source = model.currentSource
        let layoutChanged = shownSourceID != nil && source?.id != shownSourceID
        shownSourceID = source?.id

        guard model.menuBarStyle == .flag, let source, let flag = model.flag(for: source), let art = model.flagArt(for: flag) else {
            shownFlag = nil
            player.stop()
            button.image = nil
            button.attributedTitle = NSAttributedString(string: source?.shortLabel ?? "⌨︎", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .baselineOffset: 0.5,
            ])
            return
        }

        let flagChanged = flag != shownFlag
        shownFlag = flag
        if !button.title.isEmpty {
            button.title = ""
            button.imagePosition = .imageOnly
        }

        let canAnimate = item.isVisible && !screensAsleep
        switch canAnimate ? model.effectiveFlagAnimation : .off {
        case .always:
            player.loop(art.loop, key: flag)
        case .onSwitch:
            if layoutChanged {
                player.playOnce(art.burst, key: flag, then: art.still)
            } else if !player.isPlaying || flagChanged || player.isLooping {
                player.stop()
                button.image = art.still
            }
        case .off:
            player.stop()
            button.image = art.still
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for warning in warnings() {
            menu.addItem(warning)
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }

        for source in model.sources {
            let flag = model.menuBarStyle == .flag ? model.flag(for: source) : nil
            let title = flag.map { "\($0)  \(source.name)" } ?? source.name
            let item = ClosureMenuItem(title: title) { [weak model] in
                model?.perform(.select(sourceID: source.id))
            }
            item.state = source.id == model.currentSourceID ? .on : .off
            if flag == nil { item.image = model.icon(for: source).map(Self.menuSized) }
            let shortcuts = model.bindings(for: .select(sourceID: source.id)).map(\.effectiveShortcut.displayString)
            if !shortcuts.isEmpty { item.badge = NSMenuItemBadge(string: shortcuts.joined(separator: "  ")) }
            menu.addItem(item)
        }

        // What the macOS Input menu offers, so it can be hidden without losing anything.
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Emoji & Symbols") { NSApp.orderFrontCharacterPalette(nil) })
        menu.addItem(ClosureMenuItem(title: "Keyboard Settings…") { Permissions.openKeyboardSettings() })

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Settings…", keyEquivalent: ",") { [weak self] in self?.openSettings() })
        menu.addItem(ClosureMenuItem(title: "Quit Switchy", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    private func warnings() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if !model.accessibilityGranted {
            items.append(ClosureMenuItem(title: "⚠︎ Allow Accessibility access…") { Permissions.openAccessibilitySettings() })
        } else if !model.tapRunning {
            items.append(ClosureMenuItem(title: "⚠︎ Keyboard monitoring is off — open Settings") { [weak self] in self?.openSettings() })
        }
        if model.secureInputActive {
            let owner = model.secureInputOwner ?? "Another app"
            items.append(disabledItem("⚠︎ Paused: \(owner) is using secure input"))
        }
        if model.mlSwitcherRunning {
            items.append(ClosureMenuItem(title: "⚠︎ Quit MLSwitcher2 (it conflicts)") { [weak model] in model?.quitMLSwitcher() })
        }
        return items
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func menuSized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

/// Steps through pre-rendered frames on a timer. The timer runs in common run-loop modes, so the
/// flag keeps waving while a menu is open.
@MainActor
final class FlagPlayer {
    var show: (NSImage) -> Void = { _ in }
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var index = 0
    private var repeats = false
    private var finalImage: NSImage?
    private var key: String?

    var isPlaying: Bool { timer != nil }
    var isLooping: Bool { isPlaying && repeats }

    func loop(_ frames: [NSImage], key: String) {
        if isLooping && self.key == key { return }
        start(frames, key: key, repeats: true, finalImage: nil)
    }

    func playOnce(_ frames: [NSImage], key: String, then finalImage: NSImage) {
        start(frames, key: key, repeats: false, finalImage: finalImage)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        key = nil
    }

    private func start(_ frames: [NSImage], key: String, repeats: Bool, finalImage: NSImage?) {
        stop()
        guard let first = frames.first else {
            if let finalImage { show(finalImage) }
            return
        }
        self.frames = frames
        self.key = key
        self.repeats = repeats
        self.finalImage = finalImage
        index = 0
        show(first)
        let timer = Timer(timeInterval: 1 / FlagAnimationTiming.framesPerSecond, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        index += 1
        if index >= frames.count {
            guard repeats else {
                let last = finalImage
                stop()
                if let last { show(last) }
                return
            }
            index = 0
        }
        show(frames[index])
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

enum Permissions {
    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
