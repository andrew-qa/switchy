import Carbon
import Foundation
import IOKit

/// When any app turns on Secure Event Input (password fields, Terminal's "Secure Keyboard Entry",
/// some password managers), macOS hides keystrokes from every event tap, Switchy's included.
/// It's the most common reason a switcher "randomly stops working", so Switchy shows who holds it.
public enum SecureInput {
    public static var isActive: Bool { IsSecureEventInputEnabled() }

    public static func ownerPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]]
        else { return nil }
        for user in users {
            if let pid = user["kCGSSessionSecureInputPID"] as? Int, pid > 0 { return pid_t(pid) }
        }
        return nil
    }
}

public enum MenuBarPolicy {
    /// The icon is the only place Switchy can say "your shortcuts don't work", so a hidden icon
    /// comes back while permission or monitoring is missing. Secure input is left out on purpose:
    /// it flips on and off with every password field, and the icon would flicker.
    public static func showsStatusItem(userWantsIt: Bool, accessibilityGranted: Bool, monitoring: Bool) -> Bool {
        userWantsIt || !accessibilityGranted || !monitoring
    }
}

/// The floating language badge macOS (14+) shows near the text cursor on every switch.
/// In apps that don't report their caret position it appears at random spots on screen.
/// Controlled by an undocumented global default; it takes effect after logging out and back in.
public enum SystemInputIndicator {
    static var key: CFString { "TSMLanguageIndicatorEnabled" as CFString }

    public static var isHidden: Bool {
        let value = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let enabled = value as? Bool else { return false }
        return !enabled
    }

    /// Hiding writes `false`; showing removes the key so the system default applies again.
    @discardableResult
    public static func setHidden(_ hidden: Bool) -> Bool {
        CFPreferencesSetValue(key, hidden ? kCFBooleanFalse : nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
