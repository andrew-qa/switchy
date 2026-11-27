import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        let settings = SettingsWindowController(model: model)
        let firstLaunch = model.isFirstLaunch
        self.model = model
        self.settings = settings
        // Start first so the status item is created already knowing whether it should be visible.
        model.start()
        statusItem = StatusItemController(model: model) { [weak settings] in settings?.show() }
        if firstLaunch || !model.accessibilityGranted {
            settings.show()
        }
    }

    /// Opening the app again (Finder, Spotlight, `open`) shows settings, like MLSwitcher2 did.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return true
    }
}

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
