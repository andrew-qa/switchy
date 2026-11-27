import AppKit

/// The macOS Input menu (flag/letter icon) in the menu bar.
///
/// It's the same preference as System Settings → Keyboard → "Show Input menu in menu bar".
/// TextInputMenuAgent, which draws that menu, only reads it at launch; launchd restarts the agent
/// right away when it quits (KeepAlive), so quitting it applies the change.
@MainActor
enum SystemInputMenu {
    private static var domain: CFString { "com.apple.TextInputMenu" as CFString }
    private static var key: CFString { "visible" as CFString }
    private static let agentBundleID = "com.apple.TextInputMenuAgent"

    static var isVisible: Bool {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? Bool ?? true
    }

    static func setVisible(_ visible: Bool) {
        CFPreferencesSetAppValue(key, visible ? kCFBooleanTrue : kCFBooleanFalse, domain)
        CFPreferencesAppSynchronize(domain)
        restartAgent()
    }

    private static func restartAgent() {
        for agent in NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID) {
            let pid = agent.processIdentifier
            agent.terminate()
            // If it ignores the polite request, launchd still brings it back after a hard stop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSRunningApplication(processIdentifier: pid)?.forceTerminate()
            }
        }
    }
}
