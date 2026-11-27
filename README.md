# Switchy

A small, free menu bar app for macOS that switches keyboard layouts with shortcuts you choose.

- **Key combos per layout**: ⌥1 → ABC, ⌥§ → Ukrainian. The key never reaches the app, so no stray `¡`.
- **Modifier-only taps per layout**: tap Right ⌘ → Ukrainian, Left ⌘ → ABC. Left and right are told apart. A tap only counts if you press and release the modifier on its own, quickly, so ⌘C, ⌘-click and holding ⌘ never switch.
- **Next / previous layout** shortcuts, in either style.
- **Verified switching**: every switch is checked and retried (up to 4 attempts) if macOS dropped it.
- **Language code or flag** in the menu bar, optionally waving when you switch.
- **No floating tooltips.** There's an option to turn off the macOS input-source popup that jumps around the screen.
- Imports MLSwitcher2 shortcuts on first launch, if you have them.

## Why another switcher

Layout switchers tend to break on recent macOS in the same few places. Switchy is built around them:

- **Hotkeys macOS rejects.** Since macOS 15, `RegisterEventHotKey` refuses hotkeys whose only modifiers are ⌥ or ⌥⇧, which rules out ⌥1-style shortcuts. Switchy reads keys with an event tap on its own thread instead, and turns the tap back on if macOS disables it.
- **Switches that don't land.** A single `TISSelectInputSource` call doesn't always take effect, and Apple restricts it in sandboxed (App Store) apps. Switchy isn't sandboxed, looks the layout up fresh every time, checks that the switch happened, and retries.
- **The popup in random places.** That floating language indicator is macOS's own (macOS 14+), not the switcher's. Settings → "Hide the macOS input source popup" turns it off after you log out and back in.

## Requirements

- macOS 14 or later.
- To build: Xcode 26 or later (Swift 6, and `actool` support for the Icon Composer app icon).

There's no prebuilt download yet; build it from source as below.

## Build & install

```bash
scripts/build-app.sh            # → build/Switchy.app
scripts/build-app.sh --install  # also copies to /Applications and launches it
```

The script signs with your first "Apple Development" identity, or with `$SWITCHY_SIGN_IDENTITY` if set. This matters because macOS ties the Accessibility permission to the signature. With ad-hoc signing you would have to grant it again after every rebuild.

On first launch, grant **System Settings → Privacy & Security → Accessibility → Switchy**. Switchy picks up the permission within 2 seconds; no restart needed.

## Use

Click the menu bar label (`EN` / `UA`) → **Settings…**. Click **+** next to a layout and either:
- press a combo (⌥1), or
- tap modifiers on their own (Right ⌘).

Esc cancels. Right-click a shortcut to choose whether the left/right side matters. By default, combos match either side and taps match the side you recorded. Overlapping shortcuts get a red outline, and the one listed first wins.

## Troubleshooting

- **Shortcuts stop working in some apps.** A password field, Terminal's *Secure Keyboard Entry*, or some password managers turn on "secure input", which hides keystrokes from every switcher. The menu shows which app is holding it.
- **Quit MLSwitcher2.** Running both makes them fight over the same keys. Switchy warns you and offers to quit it.
- `build/Switchy.app/Contents/MacOS/Switchy --self-test` switches through every enabled layout, checks each switch, restores your layout and prints a report.
- Logs: `log stream --predicate 'subsystem == "Switchy"'`.

## Layout

```
Sources/SwitchyCore/   logic + thin system wrappers (unit-tested)
  ShortcutEngine        decides per event: swallow? fire? (pure)
  ModifierTapDetector   clean modifier-only press detection (pure)
  Modifiers / Shortcut  left/right-aware modifier model, matching, overlap, display
  InputSourceSwitcher   select → verify → retry
  KeyboardEventTap      CGEventTap on a dedicated thread
  MLSwitcherImporter    decodes MLSwitcher2's `flags | keyCode` values
Sources/Switchy/       AppKit status item + SwiftUI settings
Resources/AppIcon.icon app icon, an Icon Composer document (open it in Xcode → Icon Composer);
                       the build compiles it with actool into Assets.car + AppIcon.icns
Tests/SwitchyCoreTests/
```

`swift test` runs the suite.

## Contributing

Issues and pull requests are welcome. Please run `swift test` before sending a change, and add tests for new logic in `SwitchyCore`.

## License

MIT. See [LICENSE](LICENSE).
