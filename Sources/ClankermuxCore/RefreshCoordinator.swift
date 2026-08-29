import Foundation

/// The delay source behind the per-cycle timeout, injectable so a timeout can be tested without
/// spending wall-clock time. The injected `now` is a time *source* and cannot drive `Task.sleep`,
/// which is why this exists separately.
public protocol Sleeper: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// The coordinator's state as a value, so nothing mutable crosses to the UI.
public struct RefreshSnapshot: Sendable, Equatable {
    public let baseURL: String
    /// Nil until an accounts payload has been read successfully.
    public let accounts: [Account]?
    public let status: StatusResponse?
    public let runway: RunwayResponse?
    public let statusReceivedAt: Date?
    public let runwayReceivedAt: Date?
    public let lastSuccess: Date?
    public let lastError: String
    public let lastRunwayError: String
    public let isRefreshing: Bool

    /// Applies the current display settings, which change the view without refetching.
    public func rendered(options: ViewOptions, now: Date) -> RenderedSnapshot {
        var options = options
        options.statusReceivedAt = statusReceivedAt
        options.runwayReceivedAt = runwayReceivedAt
        let view = UsageModel.buildView(
            accounts: accounts, status: status, runway: runway, options: options, localNow: now)
        return RenderedSnapshot(
            state: accounts == nil ? .notLoaded : .loaded(view.accounts),
            view: view,
            baseURL: baseURL,
            lastError: lastError,
            lastRunwayError: lastRunwayError,
            lastSuccess: lastSuccess,
            isRefreshing: isRefreshing
        )
    }
}

public struct RenderedSnapshot: Sendable, Equatable {
    public let state: LoadState
    public let view: UsageView
    public let baseURL: String
    public let lastError: String
    public let lastRunwayError: String
    public let lastSuccess: Date?
    public let isRefreshing: Bool
}

/// Owns every refresh decision and all fetched state. Has no timers of its own: the app drives it.
public actor RefreshCoordinator {
    public typealias SnapshotHandler = @Sendable (RefreshSnapshot) async -> Void

    /// The runway projection is the expensive endpoint, so it is cached between forced refreshes.
    public static let runwayRefreshInterval: TimeInterval = 5 * 60

    private let client: any ApiClientProtocol
    private let now: @Sendable () -> Date
    private let sleeper: any Sleeper
    private let runwayRefreshInterval: TimeInterval

    private var baseURL: String
    private var requestTimeout: TimeInterval

    private var generation = 0
    private var isRefreshing = false
    private var accounts: [Account]?
    private var status: StatusResponse?
    private var runway: RunwayResponse?
    private var statusReceivedAt: Date?
    private var runwayReceivedAt: Date?
    private var lastRunwayAttempt: Date?
    private var lastRunwayError = ""
    private var lastSuccess: Date?
    private var lastError = ""

    private var activeRequests: Task<CycleResults, Never>?
    private var cycle: RefreshCycle?
    private var cycleGeneration = -1

    private var onStarted: SnapshotHandler?
    private var onFinished: SnapshotHandler?

    public init(
        client: any ApiClientProtocol,
        baseURL: String,
        requestTimeout: TimeInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        sleeper: any Sleeper = TaskSleeper(),
        runwayRefreshInterval: TimeInterval = RefreshCoordinator.runwayRefreshInterval
    ) {
        self.client = client
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.now = now
        self.sleeper = sleeper
        self.runwayRefreshInterval = runwayRefreshInterval
    }

    public func setHandlers(started: SnapshotHandler?, finished: SnapshotHandler?) {
        onStarted = started
        onFinished = finished
    }

    public func snapshot() -> RefreshSnapshot {
        RefreshSnapshot(
            baseURL: baseURL,
            accounts: accounts,
            status: status,
            runway: runway,
            statusReceivedAt: statusReceivedAt,
            runwayReceivedAt: runwayReceivedAt,
            lastSuccess: lastSuccess,
            lastError: lastError,
            lastRunwayError: lastRunwayError,
            isRefreshing: isRefreshing
        )
    }

    /// Points the coordinator at a different server and drops everything read from the old one.
    ///
    /// The coordinator is reconfigured rather than rebuilt: a fresh actor's generation cannot
    /// invalidate a request task the previous one still retains, so a slow reply from the old URL
    /// could still be applied.
    public func reconfigure(baseURL: String, timeout: TimeInterval) {
        generation += 1
        activeRequests?.cancel()
        activeRequests = nil
        cycle = nil
        isRefreshing = false
        accounts = nil
        status = nil
        runway = nil
        statusReceivedAt = nil
        runwayReceivedAt = nil
        lastRunwayAttempt = nil
        lastRunwayError = ""
        lastSuccess = nil
        lastError = ""
        self.baseURL = baseURL
        self.requestTimeout = timeout
    }

    public func refresh(forceRunway: Bool = false) async {
        // Actor isolation is not an in-flight guard: actors are reentrant across `await`, so
        // without this flag a poll interval shorter than the timeout lets each cycle supersede the
        // last and no result is ever accepted.
        guard !isRefreshing else { return }
        isRefreshing = true
        generation += 1
        let generation = self.generation
        let base = baseURL
        let timeout = max(2, requestTimeout)
        let fetchRunway =
            forceRunway
            || lastRunwayAttempt.map { now().timeIntervalSince($0) >= runwayRefreshInterval } ?? true
        cycle = RefreshCycle(requestCount: fetchRunway ? 3 : 2)
        cycleGeneration = generation
        if fetchRunway { lastRunwayAttempt = now() }
        await onStarted?(snapshot())

        let client = self.client
        let clock = self.now
        let requests = Task { () async -> CycleResults in
            async let accounts = Self.attempt(now: clock) {
                try await client.fetchAccounts(baseURL: base, timeout: timeout)
            }
            async let status = Self.attempt(now: clock) {
                try await client.fetchStatus(baseURL: base, timeout: timeout)
            }
            if fetchRunway {
                async let runway = Self.attempt(now: clock) {
                    try await client.fetchRunway(baseURL: base, timeout: timeout)
                }
                return await CycleResults(accounts: accounts, status: status, runway: runway)
            }
            return await CycleResults(accounts: accounts, status: status, runway: nil)
        }
        activeRequests = requests

        let timeoutTask = Task { [weak self] in
            do { try await self?.sleeperDelay(timeout) } catch { return }
            if Task.isCancelled { return }
            await self?.expire(generation: generation, seconds: timeout)
        }

        let results = await requests.value
        timeoutTask.cancel()
        if apply(results, generation: generation, fetchRunway: fetchRunway) {
            await onFinished?(snapshot())
        }
    }

    private func sleeperDelay(_ seconds: TimeInterval) async throws {
        try await sleeper.sleep(for: seconds)
    }

    /// Applies each response on its own. A failing sibling must not discard a successful one, so
    /// the child tasks hand back outcomes rather than throwing out of a task group.
    private func apply(_ results: CycleResults, generation: Int, fetchRunway: Bool) -> Bool {
        guard generation == self.generation, cycleGeneration == generation, cycle != nil else {
            return false
        }
        var settled = false
        for _ in 0..<(fetchRunway ? 3 : 2) where cycle?.completeOne() == true {
            settled = true
        }
        guard settled else { return false }

        activeRequests = nil
        isRefreshing = false

        var accountsError: String?
        var statusError: String?
        switch results.accounts {
        case .success(let response, _): accounts = response.accounts ?? []
        case .failure(let message): accountsError = message
        }
        switch results.status {
        case .success(let response, let receivedAt):
            status = response
            statusReceivedAt = receivedAt
        case .failure(let message):
            statusError = message
        }
        if fetchRunway, let runwayResult = results.runway {
            switch runwayResult {
            case .success(let response, let receivedAt):
                runway = response
                runwayReceivedAt = receivedAt
                lastRunwayError = ""
            case .failure(let message):
                lastRunwayError = message
            }
        }

        // A failed cycle keeps the previously fetched payloads, so the popup can show cached
        // values with a "showing cached data" note instead of going blank.
        if accountsError == nil && statusError == nil {
            lastSuccess = now()
            lastError = ""
        } else {
            lastError = [accountsError, statusError].compactMap { $0 }.joined(separator: " · ")
        }
        return true
    }

    private func expire(generation: Int, seconds: TimeInterval) async {
        guard generation == self.generation, cycleGeneration == generation,
            cycle?.expire() == true
        else { return }
        self.generation += 1
        isRefreshing = false
        activeRequests?.cancel()
        activeRequests = nil
        lastError = "Refresh timed out after \(Int(seconds))s"
        await onFinished?(snapshot())
    }

    private static func attempt<T: Sendable>(
        now: @escaping @Sendable () -> Date,
        _ body: @escaping @Sendable () async throws -> T
    ) async -> Attempt<T> {
        do {
            return .success(try await body(), now())
        } catch {
            return .failure(error.clankermuxUserMessage)
        }
    }
}

enum Attempt<T: Sendable>: Sendable {
    case success(T, Date)
    case failure(String)
}

struct CycleResults: Sendable {
    let accounts: Attempt<AccountsResponse>
    let status: Attempt<StatusResponse>
    let runway: Attempt<RunwayResponse>?
}
