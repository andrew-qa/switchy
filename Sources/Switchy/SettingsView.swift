import AppKit
import SwiftUI
import SwitchyCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Switchy"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 680))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // Recording eats keys system-wide, so it must end the moment you stop looking at Settings:
    // switching apps, clicking another window, minimising, or closing all resign key first.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
    }
}

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            StatusSection(model: model)

            Section {
                ForEach(model.sources) { source in
                    ActionRow(model: model, action: .select(sourceID: source.id), title: source.name, source: source)
                }
            } header: {
                Text("Layouts")
            } footer: {
                Text("Click + and press a combo like ⌥1, or tap modifiers on their own, like Right ⌘ (press and release without touching another key). Esc cancels. Right-click a shortcut to change whether the left/right side matters.")
            }

            Section("Cycle through layouts") {
                ActionRow(model: model, action: .next, title: "Next layout", source: nil)
                ActionRow(model: model, action: .previous, title: "Previous layout", source: nil)
            }

            MenuBarSection(model: model)

            OptionsSection(model: model)

            if model.mlSwitcherHasSettings {
                Section("MLSwitcher2") {
                    HStack {
                        Text("Copy the per-layout shortcuts from MLSwitcher2.")
                        Spacer()
                        Button("Import") { model.importFromMLSwitcher() }
                    }
                    if let count = model.lastImportCount {
                        Text(count == 0 ? "Nothing new to import." : "Imported \(count) shortcut\(count == 1 ? "" : "s").")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text(statsLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 560)
    }

    private var statsLine: String {
        let s = model.stats
        var parts = ["\(s.switches) switch\(s.switches == 1 ? "" : "es") this session"]
        parts.append("\(s.retried) needed a retry")
        parts.append("\(s.failed) failed")
        if s.tapReenabled > 0 { parts.append("monitoring revived \(s.tapReenabled)×") }
        return parts.joined(separator: " · ")
    }
}

private struct StatusSection: View {
    let model: AppModel

    var body: some View {
        if !model.accessibilityGranted {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Switchy needs Accessibility access to see your shortcuts.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("System Settings → Privacy & Security → Accessibility → turn on Switchy. It starts working within a couple of seconds; no restart needed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
                }
                .padding(.vertical, 4)
            }
        } else if !model.tapRunning {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("macOS refused keyboard monitoring.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Also allow Switchy under Privacy & Security → Input Monitoring.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Input Monitoring Settings") { Permissions.openInputMonitoringSettings() }
                }
                .padding(.vertical, 4)
            }
        }

        if model.secureInputActive || model.mlSwitcherRunning {
            Section {
                if model.secureInputActive {
                    Label(
                        "Shortcuts are paused: \(model.secureInputOwner ?? "another app") has secure input on (a password field, or Terminal's Secure Keyboard Entry). macOS hides all keystrokes from switchers while it's on.",
                        systemImage: "lock.fill"
                    )
                }
                if model.mlSwitcherRunning {
                    HStack {
                        Label("MLSwitcher2 is running and will fight over the same shortcuts.", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Quit MLSwitcher2") { model.quitMLSwitcher() }
                    }
                }
            }
        }
    }
}

private struct MenuBarSection: View {
    let model: AppModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show Switchy in the menu bar", isOn: Binding(get: { model.showStatusItem }, set: { model.setShowStatusItem($0) }))
                Text(model.showStatusItem
                    ? "Shows the current layout, its shortcuts, and a warning when shortcuts are paused."
                    : "Hidden. Open Switchy again (Spotlight or Finder) to get back here. The icon comes back by itself if shortcuts stop working.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Picker("Show layout as", selection: Binding(get: { model.menuBarStyle }, set: { model.setMenuBarStyle($0) })) {
                    Text("Language code (\(styleExample(.languageCode)))").tag(MenuBarStyle.languageCode)
                    Text("Flag (\(styleExample(.flag)))").tag(MenuBarStyle.flag)
                }
                .pickerStyle(.segmented)
                if model.menuBarStyle == .flag {
                    Text("Click a layout's flag under Layouts to pick a different one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if model.menuBarStyle == .flag {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        Picker("Wave the flag", selection: Binding(get: { model.flagAnimation }, set: { model.setFlagAnimation($0) })) {
                            Text("Never").tag(FlagAnimation.off)
                            Text("When switching").tag(FlagAnimation.onSwitch)
                            Text("Always").tag(FlagAnimation.always)
                        }
                        .pickerStyle(.segmented)
                        FlagPreview(model: model)
                    }
                    if let note = animationNote {
                        Text(note).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show the macOS Input menu", isOn: Binding(get: { model.systemInputMenuVisible }, set: { model.setSystemInputMenuVisible($0) }))
                Text("The system's own layout indicator. Same switch as System Settings → Keyboard → “Show Input menu in menu bar”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Menu bar")
        } footer: {
            if model.showStatusItem && model.systemInputMenuVisible {
                Text("Both are on, so you see the layout twice. Turning one off is enough.")
            } else if !model.showStatusItem && !model.systemInputMenuVisible {
                Text("Neither is on, so the menu bar won't show the current layout.")
            }
        }
    }
}

extension MenuBarSection {
    fileprivate var animationNote: String? {
        if model.reduceMotion && model.flagAnimation != .off {
            return "Reduce Motion is on (System Settings → Accessibility → Display), so the flag stays still."
        }
        switch model.flagAnimation {
        case .off: return nil
        case .onSwitch: return "Waves for 2 seconds after each switch, then rests."
        case .always: return "Redraws the menu bar 15 times a second, which costs a little battery. Pauses while the screen is off."
        }
    }

    /// The current layout rendered in a style, so each option previews itself.
    fileprivate func styleExample(_ style: MenuBarStyle) -> String {
        guard let source = model.currentSource ?? model.sources.first else { return style == .flag ? "🏳️" : "EN" }
        switch style {
        case .languageCode: return source.shortLabel
        case .flag: return model.flag(for: source) ?? source.shortLabel
        }
    }
}

private struct OptionsSection: View {
    let model: AppModel

    var body: some View {
        Section("Options") {
            VStack(alignment: .leading) {
                Slider(
                    value: Binding(get: { model.maxTapDuration }, set: { model.setMaxTapDuration($0) }),
                    in: 0.2...1.5,
                    step: 0.1
                ) {
                    Text("Modifier tap time limit")
                } minimumValueLabel: {
                    Text("0.2s")
                } maximumValueLabel: {
                    Text("1.5s")
                }
                Text("A modifier held longer than \(model.maxTapDuration, format: .number.precision(.fractionLength(1))) s doesn't count as a tap.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.launchAtLoginError {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Hide the macOS input source popup",
                    isOn: Binding(get: { model.hideSystemIndicator }, set: { model.setHideSystemIndicator($0) })
                )
                Text("The floating language badge macOS shows near the text cursor after each switch. In apps that don't report a cursor position it lands in random spots. This changes a system-wide setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.indicatorChangePending {
                    Text("Log out and back in for this to take effect.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct ActionRow: View {
    let model: AppModel
    let action: SwitchAction
    let title: String
    let source: InputSourceInfo?

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
            Text(title)
            if let source, source.id == model.currentSourceID {
                Circle().fill(.green).frame(width: 6, height: 6)
                    .accessibilityLabel("Current layout")
            }
            Spacer(minLength: 12)
            ForEach(model.bindings(for: action)) { binding in
                ShortcutChip(
                    binding: binding,
                    conflicting: model.conflicts.contains(binding.id),
                    onRemove: { model.removeBinding(binding.id) },
                    onMatchEitherSide: { model.setMatchEitherSide($0, for: binding.id) }
                )
            }
            recordButton
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        if let source, model.menuBarStyle == .flag {
            FlagPicker(model: model, source: source)
        } else if let source, let image = model.icon(for: source) {
            Image(nsImage: image).resizable().frame(width: 18, height: 18)
        } else if let source {
            Text(source.shortLabel)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
        } else {
            Image(systemName: action == .next ? "arrow.right.circle" : "arrow.left.circle")
                .frame(width: 18, height: 18)
        }
    }

    @ViewBuilder private var recordButton: some View {
        if model.recordingFor == action {
            Button("Press keys…  ⎋") { model.cancelRecording() }
                .buttonStyle(.borderedProminent)
        } else {
            Button {
                model.startRecording(for: action)
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!model.tapRunning || model.recordingFor != nil)
            .accessibilityLabel("Add shortcut for \(title)")
        }
    }
}

/// Exactly what the menu bar shows, at the same size, on a menu-bar-like strip.
private struct FlagPreview: View {
    let model: AppModel

    var body: some View {
        if let source = model.currentSource ?? model.sources.first,
           let flag = model.flag(for: source),
           let art = model.flagArt(for: flag) {
            Group {
                if model.effectiveFlagAnimation == .off || art.loop.isEmpty {
                    Image(nsImage: art.still)
                } else {
                    TimelineView(.periodic(from: .now, by: 1 / FlagAnimationTiming.framesPerSecond)) { context in
                        let tick = Int(context.date.timeIntervalSinceReferenceDate * FlagAnimationTiming.framesPerSecond)
                        Image(nsImage: art.loop[tick % art.loop.count])
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .accessibilityLabel("Preview of the \(source.name) flag")
        }
    }
}

/// The layout's flag; click it to choose another one or go back to automatic.
private struct FlagPicker: View {
    let model: AppModel
    let source: InputSourceInfo

    var body: some View {
        Menu {
            Picker("Flag", selection: Binding<String?>(
                get: { model.flagOverrides[source.id] },
                set: { model.setFlagOverride($0, for: source.id) }
            )) {
                Text(automaticTitle).tag(String?.none)
                Divider()
                ForEach(model.flagRegions()) { region in
                    Text("\(region.emoji)  \(region.name)").tag(String?.some(region.code))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(model.flag(for: source) ?? source.shortLabel)
                .font(.system(size: 16))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Flag for \(source.name)")
    }

    private var automaticTitle: String {
        guard let region = model.automaticFlagRegion(for: source),
              let flag = FlagEmoji.emoji(forRegion: region)
        else { return "Automatic (none)" }
        let name = Locale.current.localizedString(forRegionCode: region) ?? region
        return "Automatic — \(flag)  \(name)"
    }
}

private struct ShortcutChip: View {
    let binding: ShortcutBinding
    let conflicting: Bool
    let onRemove: () -> Void
    let onMatchEitherSide: @MainActor (Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(binding.effectiveShortcut.displayString)
                .font(.system(.body, design: .rounded).weight(.medium))
            if binding.shortcut.isModifierTap {
                Text("tap").font(.caption2).foregroundStyle(.secondary)
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove \(binding.effectiveShortcut.displayString)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(conflicting ? Color.red : .clear, lineWidth: 1.5))
        .contextMenu {
            if binding.shortcut.isSideSpecific {
                Toggle(
                    "Either side works (\(binding.shortcut.eitherSide.displayString))",
                    isOn: Binding(get: { binding.matchEitherSide }, set: onMatchEitherSide)
                )
            }
            Button("Remove", role: .destructive, action: onRemove)
        }
        .help(conflicting ? "Overlaps another shortcut. The one listed first wins." : "")
    }
}
