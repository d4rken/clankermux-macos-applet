import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Detail content")
struct DetailContentTests {

    @Test("nothing loaded yet shows the loading placeholder and the configured URL")
    func notLoaded() {
        let content = make(accounts: nil, status: nil, runway: nil)
        #expect(content.placeholder?.title == "Loading usage…")
        #expect(content.placeholder?.style == .normal)
        #expect(
            content.placeholder?.subtitle
                == "http://127.0.0.1:8080\nLast refreshed: Never")
        #expect(content.header == nil)
        #expect(content.runway == nil)
        #expect(content.accounts.isEmpty)
        #expect(content.lastRefreshText == "Last refreshed: Never")
    }

    @Test("nothing loaded plus an error shows the failure instead of the URL")
    func notLoadedWithError() {
        let content = make(
            accounts: nil, status: nil, runway: nil, lastError: "HTTP 500: Internal Server Error")
        #expect(content.placeholder?.title == "Clankermux is unavailable")
        #expect(content.placeholder?.style == .error)
        #expect(
            content.placeholder?.subtitle
                == "HTTP 500: Internal Server Error\nLast refreshed: Never")
    }

    @Test("a loaded but empty account list shows the normal header plus a notice")
    func loadedButEmpty() {
        let content = make(accounts: [], status: nil, runway: nil)
        #expect(content.placeholder == nil)
        #expect(content.header?.title == "Clankermux usage")
        #expect(
            content.header?.subtitle
                == "0 of 0 accounts available in the default routing context\nLast refreshed: Never"
        )
        #expect(content.emptyAccountsNotice?.title == "No accounts configured")
        #expect(content.pools == nil)
        #expect(content.accounts.isEmpty)
    }

    @Test("a healthy pool renders the header, runway, pool summary and every account")
    func healthy() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            lastSuccess: Fixtures.now.addingTimeInterval(-90)
        )

        #expect(
            content.header?.subtitle
                == "2 of 3 accounts available in the default routing context\n\(content.lastRefreshText)"
        )
        #expect(content.lastRefreshText.hasPrefix("Last refreshed: "))
        #expect(content.lastRefreshText.hasSuffix("(2m ago)"))

        #expect(content.runway?.title == "Quota runway · 4d")
        #expect(content.runway?.style == .normal)
        let runwayDetails = content.runway?.subtitle.components(separatedBy: "\n") ?? []
        #expect(runwayDetails.contains("Coverage: 2 of 2 active keys observed"))
        #expect(runwayDetails.contains("Model horizon: 14d"))
        #expect(runwayDetails.contains("Projection updated: <1m ago"))
        #expect(runwayDetails.contains("Cause: Account C · weekly"))

        #expect(content.pools?.title == "Pool usage")
        #expect(content.pools?.rows.map(\.label) == ["5h", "7d", "Fable"])
        #expect(content.pools?.rows[0].detail == "2 accts · 1 unknown · next in 1h")

        #expect(content.accounts.map(\.name) == ["Account A", "Account B", "Account C"])
        #expect(content.accounts[0].isDefaultCandidate)
        #expect(content.accounts[0].stateText == "Available")
        #expect(content.accounts[0].windows.map(\.label) == ["5-hour", "Weekly", "Fable"])
        #expect(content.accounts[0].windows[0].percentText == "90%")
        #expect(content.accounts[0].windows[0].forecastText == "→95%")
        #expect(content.accounts[0].windows[0].resetText == "in 1h")
        #expect(content.accounts[0].windows[1].forecastText == "")
        #expect(content.accounts[0].emptyText == nil)
        #expect(content.errorNotice == nil)
    }

    @Test("an account state line carries retry, credential and measurement notices")
    func accountStateLine() {
        let content = make(
            accounts: Fixtures.accounts(), status: Fixtures.status(), runway: Fixtures.runway())
        #expect(
            content.accounts[1].stateText
                == "Rate limited · Queueing · retry in 30m · Credential refreshable · cached usage")
        #expect(content.accounts[1].stateKey == .limited)
    }

    @Test("an account with no readable window says so instead of showing empty bars")
    func accountWithoutWindows() {
        let base = Fixtures.accounts()[2]
        let content = make(
            accounts: [Fixtures.account(base, windows: [])], status: nil, runway: nil)
        #expect(content.accounts[0].windows.isEmpty)
        #expect(content.accounts[0].emptyText == "Usage data not available yet")
    }

    @Test("a failed refresh keeps the cached view and says the data is cached")
    func cachedDataNotice() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            lastError: "Could not connect to Clankermux",
            lastSuccess: Fixtures.now.addingTimeInterval(-300)
        )
        #expect(content.header?.subtitle.contains(" · showing cached data") == true)
        #expect(content.errorNotice?.title == "Refresh failed")
        #expect(content.errorNotice?.subtitle == "Could not connect to Clankermux")
        #expect(content.accounts.count == 3)
    }

    @Test("a failed runway refresh is reported inside the runway block")
    func runwayFailureNotice() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(),
            lastRunwayError: "HTTP 503: Service Unavailable"
        )
        #expect(
            content.runway?.subtitle.contains(
                "Last runway refresh failed: HTTP 503: Service Unavailable") == true)
    }

    @Test("provider breakers distinguish provider-wide from model-scoped")
    func overloadBlocks() {
        var providers = Fixtures.defaultProviders
        providers[0] = ProviderStatus(
            provider: "anthropic",
            anyOverload: BreakerState(
                state: "open", until: Fixtures.stamp("2026-08-24T12:20:00.000Z"),
                probeActive: false),
            providerWideOverload: BreakerState(state: "open"),
            scopedLimits: providers[0].scopedLimits
        )
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(providers: providers),
            runway: Fixtures.runway()
        )
        #expect(content.overloads.count == 1)
        #expect(content.overloads[0].title == "Anthropic overload open")
        #expect(
            content.overloads[0].subtitle
                == "Provider-wide breaker · 2 accounts · retry in 20m")
        #expect(content.overloads[0].style == .error)
    }

    @Test("a breaker with no retry instant reports its probe state")
    func overloadWithoutRetry() {
        var providers = Fixtures.defaultProviders
        providers[1] = ProviderStatus(
            provider: "codex",
            anyOverload: BreakerState(state: "half_open", until: nil, probeActive: false),
            providerWideOverload: BreakerState(state: "closed"),
            scopedLimits: []
        )
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(providers: providers),
            runway: Fixtures.runway()
        )
        #expect(
            content.overloads[0].subtitle
                == "Provider/model breaker · 1 account · awaiting recovery probe")
    }

    @Test("a critical runway is styled as an error")
    func criticalRunwayStyle() {
        let content = make(
            accounts: Fixtures.accounts(),
            status: Fixtures.status(),
            runway: Fixtures.runway(outcome: Fixtures.outcome(kind: "out_now"))
        )
        #expect(content.runway?.title == "Quota runway · OUT")
        #expect(content.runway?.style == .error)
    }

    // MARK: - Helpers

    private func make(
        accounts: [Account]?,
        status: StatusResponse?,
        runway: RunwayResponse?,
        lastError: String = "",
        lastRunwayError: String = "",
        lastSuccess: Date? = nil
    ) -> DetailContent {
        let view = UsageModel.buildView(
            accounts: accounts,
            status: status,
            runway: runway,
            options: ViewOptions(statusReceivedAt: Fixtures.now, runwayReceivedAt: Fixtures.now),
            localNow: Fixtures.now
        )
        return DetailContent.make(
            state: accounts == nil ? .notLoaded : .loaded(view.accounts),
            view: view,
            baseURL: "http://127.0.0.1:8080",
            lastError: lastError,
            lastRunwayError: lastRunwayError,
            lastSuccess: lastSuccess,
            now: Fixtures.now
        )
    }
}
