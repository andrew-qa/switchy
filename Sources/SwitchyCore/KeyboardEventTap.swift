import CoreGraphics
import Foundation
import os

/// A system-wide CGEventTap that feeds `ShortcutEngine` and drops the events it claims.
///
/// Why a tap instead of Carbon `RegisterEventHotKey`:
/// - macOS 15 started rejecting hotkeys whose only modifiers are ⌥ or ⌥⇧, which is exactly ⌥1 / ⌥§.
/// - Hotkeys can't express modifier-only shortcuts or tell Left ⌘ from Right ⌘.
///
/// It runs on its own thread so a busy main thread (settings UI, menus) can never stall typing
/// system-wide, and it re-enables itself if macOS disables it for being slow.
public final class KeyboardEventTap: @unchecked Sendable {
    public typealias EffectHandler = @Sendable (EngineEffect) -> Void

    private let lock = NSLock()
    private var engine = ShortcutEngine()
    private var machPort: CFMachPort?
    private var runLoop: CFRunLoop?
    private let onEffect: EffectHandler
    private let log = Logger(subsystem: "Switchy", category: "EventTap")

    public init(onEffect: @escaping EffectHandler) {
        self.onEffect = onEffect
    }

    public var isRunning: Bool { lock.withLock { machPort != nil } }

    public func configure(bindings: [ShortcutBinding], maxTapDuration: TimeInterval) {
        lock.withLock { engine.configure(bindings: bindings, maxTapDuration: maxTapDuration) }
    }

    public func startRecording() { lock.withLock { engine.startRecording() } }
    public func cancelRecording() { lock.withLock { engine.cancelRecording() } }
    public var isRecording: Bool { lock.withLock { engine.isRecording } }

    /// Returns false when macOS refuses the tap, which means the permission is missing.
    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }
        let ready = DispatchSemaphore(value: 0)
        let started = StartFlag()

        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: switchyTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            lock.withLock {
                machPort = port
                runLoop = loop
            }
            started.value = true
            ready.signal()

            CFRunLoopRun()

            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(port)
        }
        thread.name = "Switchy.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        if started.value {
            log.info("Event tap started")
        } else {
            log.error("Event tap could not be created (permission missing?)")
        }
        return started.value
    }

    /// Also ends any recording, so a restarted tap never comes back still eating keys.
    public func stop() {
        let loop: CFRunLoop? = lock.withLock {
            engine.cancelRecording()
            let loop = runLoop
            runLoop = nil
            machPort = nil
            return loop
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// Watchdog hook. Returns true if the tap had been disabled and was switched back on.
    @discardableResult
    public func ensureEnabled() -> Bool {
        guard let port = lock.withLock({ machPort }) else { return false }
        guard !CGEvent.tapIsEnabled(tap: port) else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        log.notice("Event tap was disabled; re-enabled by watchdog")
        return true
    }

    static let eventMask: CGEventMask = [
        CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let input: EngineEvent
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = lock.withLock({ machPort }) { CGEvent.tapEnable(tap: port, enable: true) }
            log.notice("Event tap disabled by system (\(type.rawValue)); re-enabled")
            return Unmanaged.passUnretained(event)
        case .keyDown:
            input = .keyDown(
                keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: ModifierKeys(eventFlags: event.flags.rawValue),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp:
            input = .keyUp(keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)))
        case .flagsChanged:
            input = .modifiersChanged(ModifierKeys(eventFlags: event.flags.rawValue))
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            input = .otherInput
        default:
            return Unmanaged.passUnretained(event)
        }

        // Uptime instead of event.timestamp: the latter's units differ between Intel and Apple silicon.
        let now = ProcessInfo.processInfo.systemUptime
        let result = lock.withLock { engine.handle(input, at: now) }
        if let effect = result.effect { onEffect(effect) }
        return result.swallow ? nil : Unmanaged.passUnretained(event)
    }
}

private final class StartFlag: @unchecked Sendable {
    var value = false
}

private func switchyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardEventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
