import AppKit
import SwitchyCore

/// `Switchy --self-test`: switches to every enabled layout through the real switcher, verifies
/// each switch landed, restores the original layout, and prints a report. No permissions needed.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        let backend = TISInputSourceBackend()
        let switcher = InputSourceSwitcher(backend: backend)
        let sources = InputSourceCatalog.enabledKeyboardSources()
        let original = backend.currentSourceID()

        print("Enabled keyboard sources:")
        for source in sources {
            print("  \(source.shortLabel)  \(source.name)  [\(source.id)]\(source.id == original ? "  ← current" : "")")
        }

        var failures = 0
        for target in sources.map(\.id).filter({ $0 != original }) + [original].compactMap({ $0 }) {
            var outcome: SwitchOutcome?
            switcher.switchTo(target) { outcome = $0 }
            let deadline = Date().addingTimeInterval(2)
            while outcome == nil && Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            guard let outcome else {
                print("  ✘ \(target): no result within 2 s")
                failures += 1
                continue
            }
            print("  \(outcome.succeeded ? "✔︎" : "✘") \(target): \(outcome.succeeded ? "switched" : "FAILED") after \(outcome.attempts) attempt(s)")
            if !outcome.succeeded { failures += 1 }
        }

        print("Back on: \(backend.currentSourceID() ?? "?")")
        print("Secure input: \(SecureInput.isActive ? "ON (pid \(SecureInput.ownerPID().map(String.init) ?? "?"))" : "off")")
        print("macOS input popup hidden: \(SystemInputIndicator.isHidden)")
        print(failures == 0 ? "Self-test passed." : "Self-test: \(failures) failure(s).")
        return failures == 0 ? 0 : 1
    }
}
