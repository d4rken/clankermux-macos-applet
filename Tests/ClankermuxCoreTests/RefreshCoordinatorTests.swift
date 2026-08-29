import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Refresh coordinator")
struct RefreshCoordinatorTests {
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

        await coordinator.refresh(forceRunway: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts?.count == 3)
        #expect(snapshot.status?.status == "ok")
        #expect(snapshot.runway?.worstStatedOutcome?.kind == "runway")
        #expect(snapshot.lastError.isEmpty)
        #expect(snapshot.lastRunwayError.isEmpty)
        #expect(snapshot.lastSuccess == Fixtures.now)
        #expect(!snapshot.isRefreshing)
        #expect(await client.baseURLs.allSatisfy { $0 == baseURL })
    }

    @Test("the runway is fetched on the first cycle, cached for five minutes, then refetched")
    func runwayCadence() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh()
        #expect(await client.runwayCalls == 1)

        clock.advance(60)
        await coordinator.refresh()
        #expect(await client.runwayCalls == 1)
        #expect(await client.statusCalls == 2)

        clock.advance(4 * 60 + 1)
        await coordinator.refresh()
        #expect(await client.runwayCalls == 2)
    }

    @Test("a forced refresh fetches the runway inside the cache window")
    func forcedRunway() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh()
        clock.advance(10)
        await coordinator.refresh(forceRunway: true)
        #expect(await client.runwayCalls == 2)
    }

    @Test("a failing status does not discard a successful accounts reply")
    func statusFailsAccountsSucceeds() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(
            status: .failure(.http(status: 500, reason: "Internal Server Error")))
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceRunway: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts?.count == 3)
        #expect(snapshot.status == nil)
        #expect(snapshot.runway != nil)
        #expect(snapshot.lastError == "HTTP 500: Internal Server Error")
        #expect(snapshot.lastSuccess == nil)
    }

    @Test("a failing accounts reply does not discard a successful status reply")
    func accountsFailsStatusSucceeds() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(accounts: .failure(.connectionFailed))
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceRunway: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts == nil)
        #expect(snapshot.status?.status == "ok")
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

        await coordinator.refresh(forceRunway: true)
        #expect(
            await coordinator.snapshot().lastError
                == "Could not connect to Clankermux · Unexpected status response")
    }

    @Test("a failing runway is reported separately and keeps the cached projection")
    func runwayFailureKeepsProjection() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceRunway: true)
        await client.setRunway(.failure(.http(status: 503, reason: "Service Unavailable")))
        await coordinator.refresh(forceRunway: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.runway?.worstStatedOutcome?.kind == "runway")
        #expect(snapshot.lastRunwayError == "HTTP 503: Service Unavailable")
        #expect(snapshot.lastError.isEmpty)
        #expect(snapshot.lastSuccess != nil)
    }

    @Test("a cached payload survives a failed cycle so the popup can show it")
    func cachedPayloadSurvivesFailure() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceRunway: true)
        await client.setStatus(.failure(.connectionFailed))
        await client.setAccounts(.failure(.connectionFailed))
        clock.advance(30)
        await coordinator.refresh()

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts?.count == 3)
        #expect(snapshot.status?.status == "ok")
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

        await coordinator.refresh(forceRunway: true)

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.lastError == "Refresh timed out after 8s")
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
        await coordinator.refresh(forceRunway: true)
        #expect(await coordinator.snapshot().lastError == "Refresh timed out after 8s")

        let healthy = StubApiClient()
        let second = makeCoordinator(client: healthy, clock: clock)
        await second.refresh(forceRunway: true)
        #expect(await second.snapshot().lastError.isEmpty)
    }

    @Test("timer ticks and clicks during a blocked cycle issue no extra requests")
    func inFlightGuard() async throws {
        let clock = MutableClock(Fixtures.now)
        let gate = Gate()
        let client = StubApiClient(gate: gate)
        let coordinator = makeCoordinator(client: client, clock: clock)

        let first = Task { await coordinator.refresh(forceRunway: true) }
        try await waitUntil("the first cycle to reach the client") {
            await client.accountsCalls == 1
        }

        await coordinator.refresh()
        await coordinator.refresh(forceRunway: true)

        gate.open()
        await first.value

        #expect(await client.accountsCalls == 1)
        #expect(await client.statusCalls == 1)
        #expect(await client.runwayCalls == 1)
        #expect(await coordinator.snapshot().accounts?.count == 3)
    }

    @Test("a reply that outlives a reconfigure is discarded rather than applied")
    func staleReplyIsDiscarded() async throws {
        let clock = MutableClock(Fixtures.now)
        let gate = Gate()
        let client = StubApiClient(gate: gate, honorsCancellation: false)
        let coordinator = makeCoordinator(client: client, clock: clock)

        let inFlight = Task { await coordinator.refresh(forceRunway: true) }
        try await waitUntil("the cycle to reach the client") { await client.accountsCalls == 1 }

        await coordinator.reconfigure(baseURL: "http://elsewhere.test:9090", timeout: 8)
        gate.open()
        await inFlight.value

        let snapshot = await coordinator.snapshot()
        #expect(snapshot.accounts == nil)
        #expect(snapshot.status == nil)
        #expect(snapshot.runway == nil)
        #expect(snapshot.lastSuccess == nil)
        #expect(snapshot.lastError.isEmpty)
        #expect(snapshot.baseURL == "http://elsewhere.test:9090")
    }

    @Test("reconfiguring clears the cache and re-forces a runway fetch")
    func reconfigureClearsCache() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient()
        let coordinator = makeCoordinator(client: client, clock: clock)

        await coordinator.refresh(forceRunway: true)
        #expect(await coordinator.snapshot().accounts != nil)

        await coordinator.reconfigure(baseURL: "http://elsewhere.test:9090", timeout: 12)
        #expect(await coordinator.snapshot().accounts == nil)

        clock.advance(10)
        await coordinator.refresh()
        #expect(await client.runwayCalls == 2)
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
        await coordinator.refresh(forceRunway: true)

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
        await coordinator.refresh(forceRunway: true)

        let snapshot = await coordinator.snapshot()
        let withScoped = snapshot.rendered(
            options: ViewOptions(showScoped: true), now: Fixtures.now)
        let withoutScoped = snapshot.rendered(
            options: ViewOptions(showScoped: false), now: Fixtures.now)

        #expect(withScoped.state.isLoaded)
        #expect(withScoped.view.usagePools.map(\.label) == ["5h", "7d", "Fable"])
        #expect(withoutScoped.view.usagePools.map(\.label) == ["5h", "7d"])
    }

    @Test("a snapshot with no accounts renders as not loaded")
    func notLoadedSnapshot() async {
        let clock = MutableClock(Fixtures.now)
        let client = StubApiClient(accounts: .failure(.connectionFailed))
        let coordinator = makeCoordinator(client: client, clock: clock)
        await coordinator.refresh(forceRunway: true)

        let rendered = await coordinator.snapshot().rendered(
            options: ViewOptions(), now: Fixtures.now)
        #expect(rendered.state == .notLoaded)
        #expect(rendered.lastError == "Could not connect to Clankermux")
    }
}

actor SnapshotCollector {
    private(set) var started: [RefreshSnapshot] = []
    private(set) var finished: [RefreshSnapshot] = []

    func append(started snapshot: RefreshSnapshot) { started.append(snapshot) }
    func append(finished snapshot: RefreshSnapshot) { finished.append(snapshot) }
}
