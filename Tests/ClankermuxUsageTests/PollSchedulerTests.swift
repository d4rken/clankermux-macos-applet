import Foundation
import Testing

@testable import ClankermuxUsage

@MainActor
@Suite("Poll scheduler")
struct PollSchedulerTests {
    private let tick: TimeInterval = 0.02

    @Test("scheduling starts a repeating poll")
    func schedulesRepeatingPoll() async throws {
        let scheduler = PollScheduler()
        defer { scheduler.cancel() }
        let counter = Counter()

        scheduler.schedule(intervalSeconds: tick) { counter.increment() }
        #expect(scheduler.isScheduled)
        try await waitUntil("at least two ticks") { counter.value >= 2 }
    }

    @Test("rescheduling adopts the new interval")
    func reschedulesOnIntervalChange() async throws {
        let scheduler = PollScheduler()
        defer { scheduler.cancel() }
        let counter = Counter()

        scheduler.schedule(intervalSeconds: 30) { counter.increment() }
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(counter.value == 0)

        scheduler.reschedule(intervalSeconds: tick)
        try await waitUntil("a tick at the shorter interval") { counter.value >= 1 }
    }

    @Test("rescheduling before scheduling does nothing")
    func rescheduleWithoutScheduleIsInert() {
        let scheduler = PollScheduler()
        defer { scheduler.cancel() }
        scheduler.reschedule(intervalSeconds: tick)
        #expect(!scheduler.isScheduled)
    }

    @Test("cancelling stops further ticks")
    func cancellationStopsTicks() async throws {
        let scheduler = PollScheduler()
        let counter = Counter()

        scheduler.schedule(intervalSeconds: tick) { counter.increment() }
        try await waitUntil("a first tick") { counter.value >= 1 }

        scheduler.cancel()
        #expect(!scheduler.isScheduled)
        let settled = counter.value
        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(counter.value == settled)
    }

    /// The poll handler launches an async refresh; a refresh that fails must not take the timer
    /// down with it.
    @Test("a failing async refresh does not stop later ticks")
    func failingRefreshKeepsPolling() async throws {
        let scheduler = PollScheduler()
        defer { scheduler.cancel() }
        let counter = Counter()

        scheduler.schedule(intervalSeconds: tick) {
            counter.increment()
            Task { throw PollFailure.refreshFailed }
        }

        try await waitUntil("three ticks despite failing refreshes") { counter.value >= 3 }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        Issue.record("timed out waiting for \(description)", sourceLocation: sourceLocation)
    }
}

enum PollFailure: Error {
    case refreshFailed
}

@MainActor
final class Counter {
    private(set) var value = 0

    func increment() { value += 1 }
}
