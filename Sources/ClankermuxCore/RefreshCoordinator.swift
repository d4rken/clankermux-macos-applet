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

public struct RefreshSnapshot: Sendable, Equatable {
    public static func loading(baseURL: String) -> RefreshSnapshot {
        RefreshSnapshot(
            baseURL: baseURL, accounts: nil, status: nil, workloads: nil,
            accountsReceivedAt: nil, statusReceivedAt: nil, workloadsReceivedAt: nil,
            lastSuccess: nil, lastAccountsError: "", lastStatusError: "",
            lastWorkloadsError: "", isRefreshing: true)
    }

    public let baseURL: String
    public let accounts: [Account]?
    public let status: StatusResponse?
    public let workloads: WorkloadsResponse?
    public let accountsReceivedAt: Date?
    public let statusReceivedAt: Date?
    public let workloadsReceivedAt: Date?
    public let lastSuccess: Date?
    public let lastAccountsError: String
    public let lastStatusError: String
    public let lastWorkloadsError: String
    public let isRefreshing: Bool
    public var workloadsClockReceivedAt: Date? = nil

    public func serverNow(localNow: Date) -> Date {
        Formatting.anchoredNow(
            generatedAt: workloads?.generatedAt.instant,
            receivedAt: workloadsClockReceivedAt ?? workloadsReceivedAt, localNow: localNow)
    }

    public var lastError: String {
        [lastAccountsError, lastStatusError].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public func rendered(options: ViewOptions, now: Date) -> UsageView {
        UsageModel.buildView(
            accounts: accounts, workloads: workloads,
            workloadsFailed: !lastWorkloadsError.isEmpty,
            accountsFailed: !lastAccountsError.isEmpty,
            options: options, localNow: serverNow(localNow: now))
    }
}

/// Owns requests and retry state; the app drives polling and countdown ticks.
public actor RefreshCoordinator {
    public typealias SnapshotHandler = @Sendable (RefreshSnapshot) async -> Void
    public static let workloadsRefreshInterval: TimeInterval = 15

    private let client: any ApiClientProtocol
    private let now: @Sendable () -> Date
    private let sleeper: any Sleeper
    private let workloadsRefreshInterval: TimeInterval
    private var baseURL: String
    private var requestTimeout: TimeInterval
    private var generation = 0
    private var isRefreshing = false
    private var accounts: [Account]?
    private var status: StatusResponse?
    private var workloads: WorkloadsResponse?
    private var accountsReceivedAt: Date?
    private var statusReceivedAt: Date?
    private var workloadsReceivedAt: Date?
    private var workloadsClockReceivedAt: Date?
    private var lastSuccess: Date?
    private var lastAccountsError = ""
    private var lastStatusError = ""
    private var lastWorkloadsError = ""
    private var nextWorkloadsAttempt: Date?
    private var workloadFailures = 0
    private var lastExpiredKey = ""
    private var pending = Set<Resource>()
    private var cycle: RefreshCycle?
    private var fullCycle = false
    private var activeRequests: Task<Void, Never>?
    private var onStarted: SnapshotHandler?
    private var onFinished: SnapshotHandler?

    public init(
        client: any ApiClientProtocol, baseURL: String, requestTimeout: TimeInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        sleeper: any Sleeper = TaskSleeper(),
        workloadsRefreshInterval: TimeInterval = RefreshCoordinator.workloadsRefreshInterval
    ) {
        self.client = client
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.now = now
        self.sleeper = sleeper
        self.workloadsRefreshInterval = workloadsRefreshInterval
    }

    public func setHandlers(started: SnapshotHandler?, finished: SnapshotHandler?) {
        onStarted = started
        onFinished = finished
    }

    public func snapshot() -> RefreshSnapshot {
        RefreshSnapshot(
            baseURL: baseURL, accounts: accounts, status: status, workloads: workloads,
            accountsReceivedAt: accountsReceivedAt, statusReceivedAt: statusReceivedAt,
            workloadsReceivedAt: workloadsReceivedAt, lastSuccess: lastSuccess,
            lastAccountsError: lastAccountsError, lastStatusError: lastStatusError,
            lastWorkloadsError: lastWorkloadsError, isRefreshing: isRefreshing,
            workloadsClockReceivedAt: workloadsClockReceivedAt)
    }

    public func reconfigure(baseURL: String, timeout: TimeInterval) {
        generation += 1
        activeRequests?.cancel()
        activeRequests = nil
        cycle = nil
        pending = []
        isRefreshing = false
        accounts = nil
        status = nil
        workloads = nil
        accountsReceivedAt = nil
        statusReceivedAt = nil
        workloadsReceivedAt = nil
        workloadsClockReceivedAt = nil
        lastSuccess = nil
        lastAccountsError = ""
        lastStatusError = ""
        lastWorkloadsError = ""
        nextWorkloadsAttempt = nil
        workloadFailures = 0
        lastExpiredKey = ""
        self.baseURL = baseURL
        requestTimeout = timeout
    }

    public func refresh(forceWorkloads: Bool = false, workloadsOnly: Bool = false) async {
        guard !isRefreshing else { return }
        let instant = now()
        let serverInstant = snapshot().serverNow(localNow: instant)
        let expiredKey = (workloads?.workloads ?? []).compactMap { item -> String? in
            guard let deadline = item.weekly?.period?.endsAt.instant, deadline <= serverInstant
            else {
                return nil
            }
            return "\(item.id ?? ""):\(deadline.timeIntervalSince1970)"
        }.sorted().joined(separator: "|")
        let newExpiry = !expiredKey.isEmpty && expiredKey != lastExpiredKey && workloadFailures == 0
        let fetchWorkloads =
            forceWorkloads || newExpiry
            || nextWorkloadsAttempt.map { instant >= $0 } ?? true
        if workloadsOnly && !fetchWorkloads { return }
        isRefreshing = true
        generation += 1
        let currentGeneration = generation
        let base = baseURL
        let timeout = max(2, requestTimeout)
        fullCycle = !workloadsOnly
        pending = workloadsOnly ? [] : [.accounts, .status]
        if fetchWorkloads {
            pending.insert(.workloads)
            lastExpiredKey = expiredKey
            nextWorkloadsAttempt = instant.addingTimeInterval(workloadsRefreshInterval)
        }
        cycle = RefreshCycle(requestCount: pending.count)
        let resources = pending
        let client = self.client
        let clock = self.now
        await onStarted?(snapshot())
        guard generation == currentGeneration else { return }

        let requests = Task {
            await withTaskGroup(of: Void.self) { group in
                for resource in resources {
                    group.addTask {
                        let result: ResourceResult
                        do {
                            switch resource {
                            case .accounts:
                                result = .accounts(
                                    try await client.fetchAccounts(baseURL: base, timeout: timeout))
                            case .status:
                                result = .status(
                                    try await client.fetchStatus(baseURL: base, timeout: timeout))
                            case .workloads:
                                result = .workloads(
                                    try await client.fetchWorkloads(baseURL: base, timeout: timeout)
                                )
                            }
                        } catch {
                            result = .failure(error.clankermuxUserMessage)
                        }
                        await self.receive(
                            result, resource: resource, generation: currentGeneration,
                            receivedAt: clock())
                    }
                }
            }
        }
        activeRequests = requests
        let timeoutTask = Task { [weak self, sleeper] in
            do { try await sleeper.sleep(for: timeout) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.expire(generation: currentGeneration, seconds: timeout)
        }
        await requests.value
        timeoutTask.cancel()
    }

    private func receive(
        _ result: ResourceResult, resource: Resource, generation: Int, receivedAt: Date
    ) async {
        guard generation == self.generation, pending.remove(resource) != nil else { return }
        switch result {
        case .accounts(let response):
            accounts = response.accounts ?? []
            accountsReceivedAt = receivedAt
            lastAccountsError = ""
        case .status(let response):
            status = response
            statusReceivedAt = receivedAt
            lastStatusError = ""
        case .workloads(let response):
            if workloadsClockReceivedAt == nil || response.generatedAt != workloads?.generatedAt {
                workloadsClockReceivedAt = receivedAt
            }
            workloads = response
            workloadsReceivedAt = receivedAt
            lastWorkloadsError = ""
        case .failure(let message):
            setError(message, for: resource)
        }
        if resource == .workloads { scheduleWorkloads(failed: !lastWorkloadsError.isEmpty) }
        if cycle?.completeOne() == true {
            finish()
            await onFinished?(snapshot())
        }
    }

    private func finish() {
        activeRequests = nil
        isRefreshing = false
        if fullCycle && lastAccountsError.isEmpty && lastStatusError.isEmpty { lastSuccess = now() }
    }

    private func setError(_ message: String, for resource: Resource) {
        switch resource {
        case .accounts: lastAccountsError = message
        case .status: lastStatusError = message
        case .workloads: lastWorkloadsError = message
        }
    }

    private func scheduleWorkloads(failed: Bool) {
        workloadFailures = failed ? min(workloadFailures + 1, 5) : 0
        let delay = min(300, workloadsRefreshInterval * pow(2, Double(workloadFailures)))
        nextWorkloadsAttempt = now().addingTimeInterval(delay)
    }

    private func expire(generation: Int, seconds: TimeInterval) async {
        guard generation == self.generation, cycle?.expire() == true else { return }
        self.generation += 1
        activeRequests?.cancel()
        let message = "Refresh timed out after \(Int(seconds))s"
        for resource in pending { setError(message, for: resource) }
        if pending.contains(.workloads) { scheduleWorkloads(failed: true) }
        pending = []
        finish()
        await onFinished?(snapshot())
    }
}

private enum Resource: Sendable, Hashable { case accounts, status, workloads }
private enum ResourceResult: Sendable {
    case accounts(AccountsResponse)
    case status(StatusResponse)
    case workloads(WorkloadsResponse)
    case failure(String)
}
