import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Refresh coordinator")
struct RefreshCoordinatorTests {
    @Test("server clock skew is corrected without rejuvenating a repeated cached envelope")
    func serverClock() async {
        let clock = MutableClock(Fixtures.now.addingTimeInterval(3600))
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh()
        var view = await coordinator.snapshot().rendered(options: ViewOptions(), now: clock.now)
        #expect(view.workloads[0].signal.numeric)
        clock.advance(180)
        await coordinator.refresh(forceWorkloads: true)
        view = await coordinator.snapshot().rendered(options: ViewOptions(), now: clock.now)
        #expect(view.workloads[0].stale)
    }

    @Test("workloads refresh independently of account polling")
    func independentCadence() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh()
        clock.advance(15)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 2)
        #expect(await client.accountsCalls == 1)
        #expect(await client.statusCalls == 1)
        #expect(await coordinator.snapshot().lastSuccess == Fixtures.now)
    }

    @Test(
        "workload failures back off, manual refresh bypasses backoff, and success restores cadence")
    func workloadBackoff() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(workloads: .failure(.connectionFailed))
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh()
        clock.advance(15)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 1)
        clock.advance(15)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 2)
        clock.advance(30)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 2)
        await client.setWorkloads(.success(Fixtures.workloads()))
        await coordinator.refresh(forceWorkloads: true)
        #expect(await client.workloadsCalls == 3)
        clock.advance(15)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 4)
    }

    @Test("a newly expired deadline refreshes once without repeatedly bypassing the cache")
    func expiredDeadline() async {
        let clock = MutableClock(Fixtures.now)
        var workloads = Fixtures.workloads()
        workloads.workloads?[0].weekly?.period?.endsAt = Fixtures.timestamp(5)
        let client = StubApiClient(workloads: .success(workloads))
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh()
        clock.advance(5)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 2)
        clock.advance(1)
        await coordinator.refresh(workloadsOnly: true)
        #expect(await client.workloadsCalls == 2)
        #expect(
            await coordinator.snapshot().rendered(options: ViewOptions(), now: clock.now).workloads[
                0
            ]
            .expired == true)
    }

    private let baseURL = "http://clankermux.test:8080"

    private func makeCoordinator(
        client: StubApiClient,
        clock: MutableClock,
        sleeper: any Sleeper = NeverSleeper(),
        requestTimeout: TimeInterval = 8
    ) -> RefreshCoordinator {
        RefreshCoordinator(
            client: client,
            baseURL: baseURL,
            requestTimeout: requestTimeout,
            now: { clock.now },
            sleeper: sleeper
        )
    }

    @Test("a successful cycle caches every payload and clears the error")
    func successfulCycle() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts?.count == 3)
        #expect(snapshot.status?.serviceState == "ready")
        #expect(snapshot.workloads?.workloads?.first?.weekly?.outcome == "exhausts_before_end")
        #expect(snapshot.lastError.isEmpty)
        #expect(snapshot.lastWorkloadsError.isEmpty)
        #expect(snapshot.lastSuccess == Fixtures.now)
        #expect(!snapshot.isRefreshing)
        #expect(await client.baseURLs.allSatisfy { $0 == baseURL })
    }

    @Test("the workloads is fetched on the first cycle, cached for fifteen seconds, then refetched")
    func workloadsCadence() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh()
        #expect(await client.workloadsCalls == 1)

        clock.advance(10)
        await coordinator.refresh()
        #expect(await client.workloadsCalls == 1)
        #expect(await client.statusCalls == 2)

        clock.advance(6)
        await coordinator.refresh()
        #expect(await client.workloadsCalls == 2)
    }

    @Test("a forced refresh fetches the workloads inside the cache window")
    func forcedWorkloads() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh()
        clock.advance(10)
        await coordinator.refresh(forceWorkloads: true)
        #expect(await client.workloadsCalls == 2)
    }

    @Test("a failing status does not discard a successful accounts reply")
    func statusFailsAccountsSucceeds() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(
            status: .failure(.http(status: 500, reason: "Internal Server Error")))
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts?.count == 3)
        #expect(snapshot.status == nil)
        #expect(snapshot.workloads != nil)
        #expect(snapshot.lastError == "HTTP 500: Internal Server Error")
        #expect(snapshot.lastSuccess == nil)
    }

    @Test("a failing accounts reply does not discard a successful status reply")
    func accountsFailsStatusSucceeds() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(accounts: .failure(.connectionFailed))
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts == nil)
        #expect(snapshot.status?.serviceState == "ready")
        #expect(snapshot.lastError == "Could not connect to Clankermux")
    }

    @Test("two failures are joined into one message")
    func bothFail() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(
            status: .failure(.unexpectedResponse(label: "status")),
            accounts: .failure(.connectionFailed)
        )
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)
        #expect(
            await coordinator.snapshot().lastError
                == "Could not connect to Clankermux · Unexpected status response")
    }

    @Test("a failing workloads is reported separately and keeps the cached projection")
    func workloadsFailureKeepsProjection() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)
        await client.setWorkloads(.failure(.http(status: 503, reason: "Service Unavailable")))
        await coordinator.refresh(forceWorkloads: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.workloads?.workloads?.first?.weekly?.outcome == "exhausts_before_end")
        #expect(snapshot.lastWorkloadsError == "HTTP 503: Service Unavailable")
        #expect(snapshot.lastError.isEmpty)
        #expect(snapshot.lastSuccess != nil)
    }

    @Test("a cached payload survives a failed cycle so the popup can show it")
    func cachedPayloadSurvivesFailure() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)
        await client.setStatus(.failure(.connectionFailed))
        await client.setAccounts(.failure(.connectionFailed))
        clock.advance(30)
        await coordinator.refresh()

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts?.count == 3)
        #expect(snapshot.status?.serviceState == "ready")
        #expect(snapshot.lastSuccess == Fixtures.now)
        #expect(!snapshot.lastError.isEmpty)
    }

    @Test("a cycle that outruns the request timeout reports the timeout")
    func timesOut() async {
        let clock = MutableClock(Fixtures.now)
        let gate = Gate()
        let client = StubApiClient(gate: gate)
        let coordinator = makeCoordinator(
            client: client, clock: clock, sleeper: ImmediateSleeper(), requestTimeout: 8)

        await coordinator.refresh(forceWorkloads: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.lastAccountsError == "Refresh timed out after 8s")
        #expect(snapshot.accounts == nil)
        #expect(!snapshot.isRefreshing)
    }

    @Test("a refresh is possible again after a timeout")
    func recoversFromTimeout() async {
        let clock = MutableClock(Fixtures.now)
        let gate = Gate()
        let timedOut = StubApiClient(gate: gate)
        let coordinator = makeCoordinator(
            client: timedOut, clock: clock, sleeper: ImmediateSleeper())
        await coordinator.refresh(forceWorkloads: true)
        #expect(await coordinator.snapshot().lastAccountsError == "Refresh timed out after 8s")

        let healthy = StubApiClient()
        let second = makeCoordinator(client: healthy, clock: clock)
        await second.refresh(forceWorkloads: true)
        #expect(await second.snapshot().lastError.isEmpty)
    }

    @Test("timer ticks and clicks during a blocked cycle issue no extra requests")
    func inFlightGuard() async throws {
        let clock = MutableClock(Fixtures.now)
        let gate = Gate()
        let client = StubApiClient(gate: gate)
        let coordinator = makeCoordinator(client: client, clock: clock)

        let first = Task { await coordinator.refresh(forceWorkloads: true) }
        try await waitUntil("the first cycle to reach the client") {
            await client.accountsCalls == 1
        }

        await coordinator.refresh()
        await coordinator.refresh(forceWorkloads: true)

        gate.open()
        await first.value

        #expect(await client.accountsCalls == 1)
        #expect(await client.statusCalls == 1)
        #expect(await client.workloadsCalls == 1)
        #expect(await coordinator.snapshot().accounts?.count == 3)
    }

    @Test("a reply that outlives a reconfigure is discarded rather than applied")
    func staleReplyIsDiscarded() async throws {
        let clock = MutableClock(Fixtures.now)
        let gate = Gate()
        let client = StubApiClient(gate: gate, honorsCancellation: false)
        let coordinator = makeCoordinator(client: client, clock: clock)

        let inFlight = Task { await coordinator.refresh(forceWorkloads: true) }
        try await waitUntil("the cycle to reach the client") { await client.accountsCalls == 1 }

        await coordinator.reconfigure(baseURL: "http://elsewhere.test:9090", timeout: 8)
        gate.open()
        await inFlight.value

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts == nil)
        #expect(snapshot.status == nil)
        #expect(snapshot.workloads == nil)
        #expect(snapshot.lastSuccess == nil)
        #expect(snapshot.lastError.isEmpty)
        #expect(snapshot.baseURL == "http://elsewhere.test:9090")
    }

    @Test("reconfiguring clears the cache and re-forces a workloads fetch")
    func reconfigureClearsCache() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceWorkloads: true)
        #expect(await coordinator.snapshot().accounts != nil)

        await coordinator.reconfigure(baseURL: "http://elsewhere.test:9090", timeout: 12)
        #expect(await coordinator.snapshot().accounts == nil)

        clock.advance(10)
        await coordinator.refresh()
        #expect(await client.workloadsCalls == 2)
        #expect(await client.baseURLs.last == "http://elsewhere.test:9090")
        #expect(await client.timeouts.last == 12)
    }

    @Test("refresh transitions publish a started and a finished snapshot")
    func publishesTransitions() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)
        let collector = SnapshotCollector()

        await coordinator.setHandlers(
            started: { snapshot in await collector.append(started: snapshot) },
            finished: { snapshot in await collector.append(finished: snapshot) }
        )
        await coordinator.refresh(forceWorkloads: true)

        #expect(await collector.started.count == 1)
        #expect(await collector.started.first?.isRefreshing == true)
        #expect(await collector.started.first?.accounts == nil)
        #expect(await collector.finished.count == 1)
        #expect(await collector.finished.first?.isRefreshing == false)
        #expect(await collector.finished.first?.accounts?.count == 3)
    }

    @Test("a snapshot renders through the current display settings")
    func snapshotRendersWithOptions() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh(forceWorkloads: true)

        let snapshot = await coordinator.snapshot()
        let withScoped = snapshot.rendered(
            options: ViewOptions(showScoped: true), now: Fixtures.now)
        let withoutScoped = snapshot.rendered(
            options: ViewOptions(showScoped: false), now: Fixtures.now)

        #expect(!withScoped.accounts.isEmpty)
        #expect(withScoped.workloads.map(\.label) == ["Claude", "GPT", "Fable"])
        #expect(withoutScoped.workloads.map(\.label) == ["Claude", "GPT"])
    }

    @Test("a snapshot with no accounts renders as not loaded")
    func notLoadedSnapshot() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(accounts: .failure(.connectionFailed))
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh(forceWorkloads: true)

        let rendered = await coordinator.snapshot().rendered(
            options: ViewOptions(), now: Fixtures.now)
        #expect(rendered.accounts.isEmpty)
        #expect(await coordinator.snapshot().lastError == "Could not connect to Clankermux")
    }
}

actor SnapshotCollector {
    private(set) var started: [RefreshSnapshot] = []
    private(set) var finished: [RefreshSnapshot] = []

    func append(started snapshot: RefreshSnapshot) { started.append(snapshot) }
    func append(finished snapshot: RefreshSnapshot) { finished.append(snapshot) }
}
