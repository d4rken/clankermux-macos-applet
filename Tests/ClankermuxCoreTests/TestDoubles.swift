import Foundation
import Testing

@testable import ClankermuxCore

/// A one-shot barrier the stub client waits on, so a test can hold a request open.
final class Gate: @unchecked Sendable {
    private enum State {
        case closed
        case opened
        case cancelled
    }

    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, any Error>] = []
    private var state: State = .closed

    /// Waits, and gives up as soon as the surrounding task is cancelled.
    func wait() async throws {
        try await withTaskCancellationHandler {
            try await enqueue()
        } onCancel: {
            cancel()
        }
    }

    /// Waits without ever noticing cancellation, modelling a client that keeps going after the
    /// coordinator has moved on.
    func waitIgnoringCancellation() async throws {
        try await enqueue()
    }

    func open() { finish(.opened) }

    func cancel() { finish(.cancelled) }

    private func enqueue() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            lock.lock()
            switch state {
            case .opened:
                lock.unlock()
                continuation.resume()
            case .cancelled:
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            case .closed:
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    private func finish(_ newState: State) {
        lock.lock()
        guard case .closed = state else {
            lock.unlock()
            return
        }
        state = newState
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in pending {
            if case .opened = newState {
                continuation.resume()
            } else {
                continuation.resume(throwing: CancellationError())
            }
        }
    }
}

final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// Never lets the per-cycle timeout fire; the coordinator cancels it once the requests settle.
struct NeverSleeper: Sleeper {
    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 3_600 * 1_000_000_000)
    }
}

/// Fires the per-cycle timeout at once, so a timeout is testable without wall-clock time.
struct ImmediateSleeper: Sleeper {
    func sleep(for seconds: TimeInterval) async throws {}
}

actor StubApiClient: ApiClientProtocol {
    private(set) var statusCalls = 0
    private(set) var accountsCalls = 0
    private(set) var runwayCalls = 0
    private(set) var baseURLs: [String] = []
    private(set) var timeouts: [TimeInterval] = []

    private var statusResult: Result<StatusResponse, ApiError>
    private var accountsResult: Result<AccountsResponse, ApiError>
    private var runwayResult: Result<RunwayResponse, ApiError>
    private let gate: Gate?
    private let honorsCancellation: Bool

    init(
        status: Result<StatusResponse, ApiError> = .success(Fixtures.status()),
        accounts: Result<AccountsResponse, ApiError> = .success(
            AccountsResponse(
                schema: "clankermux.public.accounts.v1", accounts: Fixtures.accounts())),
        runway: Result<RunwayResponse, ApiError> = .success(Fixtures.runway()),
        gate: Gate? = nil,
        honorsCancellation: Bool = true
    ) {
        self.statusResult = status
        self.accountsResult = accounts
        self.runwayResult = runway
        self.gate = gate
        self.honorsCancellation = honorsCancellation
    }

    func setStatus(_ result: Result<StatusResponse, ApiError>) { statusResult = result }
    func setAccounts(_ result: Result<AccountsResponse, ApiError>) { accountsResult = result }
    func setRunway(_ result: Result<RunwayResponse, ApiError>) { runwayResult = result }

    func fetchStatus(baseURL: String, timeout: TimeInterval) async throws -> StatusResponse {
        statusCalls += 1
        record(baseURL: baseURL, timeout: timeout)
        try await passGate()
        return try statusResult.get()
    }

    func fetchAccounts(baseURL: String, timeout: TimeInterval) async throws -> AccountsResponse {
        accountsCalls += 1
        record(baseURL: baseURL, timeout: timeout)
        try await passGate()
        return try accountsResult.get()
    }

    func fetchRunway(baseURL: String, timeout: TimeInterval) async throws -> RunwayResponse {
        runwayCalls += 1
        record(baseURL: baseURL, timeout: timeout)
        try await passGate()
        return try runwayResult.get()
    }

    private func record(baseURL: String, timeout: TimeInterval) {
        baseURLs.append(baseURL)
        timeouts.append(timeout)
    }

    private func passGate() async throws {
        guard let gate else { return }
        if honorsCancellation {
            try await gate.wait()
        } else {
            try await gate.waitIgnoringCancellation()
        }
    }
}

func waitUntil(
    _ description: String,
    timeout: TimeInterval = 5,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 500_000)
    }
    Issue.record("timed out waiting for \(description)", sourceLocation: sourceLocation)
}
