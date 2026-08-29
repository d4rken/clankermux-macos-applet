import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Panel content")
struct PanelContentTests {

    @Test("nothing loaded yet shows the neutral loading placeholder")
    func notLoaded() {
        let content = make(accounts: nil, status: nil, runway: nil)
        #expect(content.runwayText == "Clankermux …")
        #expect(content.runwayIsMuted)
        #expect(content.meters.isEmpty)
        #expect(!content.showsEmptyPlaceholder)
        #expect(content.tooltip == "Loading Clankermux usage…")
    }

    @Test("nothing loaded plus an error shows the error marker and the error text")
    func notLoadedWithError() {
        let content = make(
            accounts: nil, status: nil, runway: nil,
            lastError: "Could not connect to Clankermux")
        #expect(content.runwayText == "Clankermux !")
        #expect(content.runwaySeverity == .warning)
        #expect(!content.runwayIsMuted)
        #expect(content.meters.isEmpty)
        #expect(content.tooltip == "Could not connect to Clankermux")
    }

    @Test("a loaded but empty account list is not the loading state")
    func loadedButEmpty() {
        let content = make(accounts: [], status: nil, runway: nil)
        #expect(content.runwayText == "R –")
        #expect(!content.runwayIsMuted)
        #expect(content.meters.isEmpty)
        #expect(content.showsEmptyPlaceholder)
        #expect(content.tooltip.contains("Quota runway: –"))
    }

    @Test("a healthy pool leads with the runway and one meter per pool")
    func healthy() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(pool: pool(configured: 3, defaultRoutable: 3)),
            runway: Fixtures.runway()
        )
        #expect(content.runwayText == "R 4d")
        #expect(content.runwaySeverity == .normal)
        #expect(content.meters.map(\.label) == ["5h", "7d", "Fable"])
        #expect(content.meters.map(\.percent) == [38, 50, 70])
        #expect(content.meters.map(\.severity) == [.normal, .normal, .normal])
        #expect(!content.showsEmptyPlaceholder)
    }

    @Test("degraded availability adds the account marker and raises severity")
    func degradedAvailability() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway()
        )
        #expect(content.runwayText == "R 4d · 2/3!")
        #expect(content.runwaySeverity == .warning)
    }

    @Test("an open provider breaker adds the hourglass and raises severity")
    func overload() {
        var providers = Fixtures.defaultProviders
        providers[0] = ProviderStatus(
            provider: "anthropic",
            anyOverload: BreakerState(state: "open", until: nil, probeActive: true),
            providerWideOverload: BreakerState(state: "closed"),
            scopedLimits: providers[0].scopedLimits
        )
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(
                pool: pool(configured: 3, defaultRoutable: 3), providers: providers),
            runway: Fixtures.runway()
        )
        #expect(content.runwayText == "R 4d ⏳")
        #expect(content.runwaySeverity == .warning)
        #expect(
            content.tooltip.contains(
                "Anthropic provider or model scope overload open · recovery probe active"))
    }

    @Test("no routable account at all is critical whatever the runway says")
    func zeroRoutable() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(pool: pool(configured: 3, defaultRoutable: 0)),
            runway: Fixtures.runway()
        )
        #expect(content.runwayText == "R 4d · 0/3!")
        #expect(content.runwaySeverity == .critical)
    }

    @Test("the tooltip states runway, coverage, availability and every pool")
    func tooltipLines() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            lastSuccess: Fixtures.now.addingTimeInterval(-120)
        )
        #expect(
            content.tooltip.components(separatedBy: "\n") == [
                "Quota runway: 4d",
                "Projected quota run-out: \(Formatting.formatTimestamp(Fixtures.now.addingTimeInterval(4 * 24 * 3600)))",
                "Coverage: 2 of 2 active keys observed",
                "Availability: 2 of 3 accounts in the default routing context",
                "5h: 38% mean usage across 2 accounts · 1 unknown",
                "7d: 50% mean usage across 3 accounts",
                "Fable: 70% mean usage across 2 accounts",
                "Updated 2m ago",
            ])
    }

    @Test("both failure notes appear in the tooltip, and the failure replaces the age line")
    func tooltipFailures() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            lastError: "HTTP 500: Internal Server Error",
            lastRunwayError: "Could not connect to Clankermux",
            lastSuccess: Fixtures.now.addingTimeInterval(-120)
        )
        let lines = content.tooltip.components(separatedBy: "\n")
        #expect(lines.contains("Last runway refresh failed: Could not connect to Clankermux"))
        #expect(lines.contains("Last refresh failed: HTTP 500: Internal Server Error"))
        #expect(!lines.contains { $0.hasPrefix("Updated ") })
    }

    @Test("an unused scoped family is dropped from the panel but stays in the tooltip")
    func scopedFamilyHiddenInPanel() {
        var providers = Fixtures.defaultProviders
        providers[0] = ProviderStatus(
            provider: "anthropic",
            anyOverload: Fixtures.closedBreaker,
            providerWideOverload: Fixtures.closedBreaker,
            scopedLimits: [
                UsageAggregate(
                    scopeId: "spark", label: "Spark", meanUtilizationPct: 0,
                    contributingAccountCount: 1, unknownAccountCount: 0)
            ]
        )
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(
                pool: pool(configured: 3, defaultRoutable: 3), providers: providers),
            runway: Fixtures.runway()
        )
        #expect(content.meters.map(\.label) == ["5h", "7d"])
        #expect(content.tooltip.contains("Spark: 0% mean usage across 1 accounts"))
    }

    // MARK: - Helpers

    private func pool(configured: Double, defaultRoutable: Double) -> PoolInfo {
        PoolInfo(
            configured: configured,
            configuredPresence: .present,
            defaultRoutable: defaultRoutable,
            defaultRoutablePresence: .present,
            paused: 0,
            rateLimited: 0,
            usageExhausted: 0,
            nextAvailableAt: nil
        )
    }

    private func make(
        accounts: [Account]?,
        status: StatusResponse?,
        runway: RunwayResponse?,
        lastError: String = "",
        lastRunwayError: String = "",
        lastSuccess: Date? = nil
    ) -> PanelContent {
        let view = UsageModel.buildView(
            accounts: accounts,
            status: status,
            runway: runway,
            options: ViewOptions(statusReceivedAt: Fixtures.now, runwayReceivedAt: Fixtures.now),
            localNow: Fixtures.now
        )
        return PanelContent.make(
            state: accounts == nil ? .notLoaded : .loaded(view.accounts),
            view: view,
            lastError: lastError,
            lastRunwayError: lastRunwayError,
            lastSuccess: lastSuccess,
            now: Fixtures.now
        )
    }
}
