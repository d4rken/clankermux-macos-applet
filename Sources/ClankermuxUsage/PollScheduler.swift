import Foundation

@MainActor
protocol PollScheduling: AnyObject {
    var isScheduled: Bool { get }
    func schedule(intervalSeconds: TimeInterval, handler: @escaping @MainActor () -> Void)
    func reschedule(intervalSeconds: TimeInterval)
    func cancel()
}

/// The repeating poll timer.
///
/// Backed by a `DispatchSourceTimer` rather than a `Timer`: a timer in the default run loop mode
/// stops firing while a menu tracks, which would stall polling for as long as a menu stays open.
@MainActor
final class PollScheduler: PollScheduling {
    private var source: DispatchSourceTimer?
    private var handler: (@MainActor () -> Void)?
    private var intervalSeconds: TimeInterval = 30

    var isScheduled: Bool { source != nil }

    func schedule(intervalSeconds: TimeInterval, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        self.intervalSeconds = intervalSeconds
        arm()
    }

    func reschedule(intervalSeconds: TimeInterval) {
        guard handler != nil else { return }
        self.intervalSeconds = intervalSeconds
        arm()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }

    private func arm() {
        source?.cancel()
        let seconds = max(0.001, intervalSeconds)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + seconds,
            repeating: seconds,
            leeway: .milliseconds(seconds >= 1 ? 500 : 1)
        )
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handler?() }
        }
        source = timer
        timer.resume()
    }
}
