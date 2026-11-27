import Foundation

@MainActor
public protocol InputSourceBackend: AnyObject {
    func currentSourceID() -> String?
    /// Returns false if the source can't be found or the OS rejects the request.
    func selectSource(id: String) -> Bool
}

public struct SwitchOutcome: Equatable, Sendable {
    public var targetID: String
    /// 0 when the target was already active.
    public var attempts: Int
    public var succeeded: Bool
}

/// Selects an input source and checks that it actually became current, retrying a few times.
///
/// A single `TISSelectInputSource` call can be dropped (stale handle after sleep, sandbox, the
/// system busy re-reading layouts), and then the shortcut silently does nothing. Checking the
/// result and retrying fixes that.
@MainActor
public final class InputSourceSwitcher {
    public typealias Work = @MainActor @Sendable () -> Void
    public typealias Scheduler = @MainActor (TimeInterval, @escaping Work) -> Void

    public static let defaultRetryDelays: [TimeInterval] = [0.03, 0.08, 0.2]

    private let backend: InputSourceBackend
    private let retryDelays: [TimeInterval]
    private let schedule: Scheduler
    private var generation = 0

    /// The source a switch is still being verified for. "Next" uses it so rapid presses advance properly.
    public private(set) var pendingTargetID: String?

    public init(
        backend: InputSourceBackend,
        retryDelays: [TimeInterval] = InputSourceSwitcher.defaultRetryDelays,
        schedule: @escaping Scheduler = InputSourceSwitcher.mainQueueSchedule
    ) {
        self.backend = backend
        self.retryDelays = retryDelays
        self.schedule = schedule
    }

    public static func mainQueueSchedule(_ delay: TimeInterval, _ work: @escaping Work) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { work() }
        }
    }

    public var effectiveCurrentID: String? {
        pendingTargetID ?? backend.currentSourceID()
    }

    /// A newer request supersedes any switch still being retried.
    public func switchTo(_ id: String, completion: (@MainActor (SwitchOutcome) -> Void)? = nil) {
        generation += 1
        let gen = generation
        if backend.currentSourceID() == id {
            pendingTargetID = nil
            completion?(SwitchOutcome(targetID: id, attempts: 0, succeeded: true))
            return
        }
        pendingTargetID = id
        attempt(id, number: 1, generation: gen, completion: completion)
    }

    private func attempt(_ id: String, number: Int, generation gen: Int, completion: (@MainActor (SwitchOutcome) -> Void)?) {
        guard gen == generation else { return }
        _ = backend.selectSource(id: id)
        if backend.currentSourceID() == id {
            finish(SwitchOutcome(targetID: id, attempts: number, succeeded: true), completion)
            return
        }
        guard number <= retryDelays.count else {
            finish(SwitchOutcome(targetID: id, attempts: number, succeeded: false), completion)
            return
        }
        schedule(retryDelays[number - 1]) { [weak self] in
            guard let self, gen == self.generation else { return }
            // The switch may simply have landed late; only select again if it really didn't.
            if self.backend.currentSourceID() == id {
                self.finish(SwitchOutcome(targetID: id, attempts: number, succeeded: true), completion)
            } else {
                self.attempt(id, number: number + 1, generation: gen, completion: completion)
            }
        }
    }

    private func finish(_ outcome: SwitchOutcome, _ completion: (@MainActor (SwitchOutcome) -> Void)?) {
        pendingTargetID = nil
        completion?(outcome)
    }
}
