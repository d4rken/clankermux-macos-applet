import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Panel content")
struct PanelContentTests {
    private func make(
        _ snapshot: RefreshSnapshot = Fixtures.snapshot(), display: PanelDisplay = .compact,
        showScoped: Bool = true, now: Date = Fixtures.now
    ) -> PanelContent {
        PanelContent.make(
            snapshot: snapshot,
            view: snapshot.rendered(options: ViewOptions(showScoped: showScoped), now: now),
            display: display, showScoped: showScoped, now: now)
    }

    @Test("pace bars hide fully paused providers and their families, then restore them on resume")
    func pausedProviders() {
        var accounts = Fixtures.accounts()
        for index in accounts.indices where accounts[index].provider == "anthropic" {
            accounts[index].availability?.state = "paused"
        }
        let snapshot = Fixtures.snapshot(accounts: accounts)
        let panel = make(snapshot)
        #expect(panel.meters.map(\.label) == ["GPT"])
        #expect(panel.tooltip.contains("Claude"))

        accounts[0].availability?.state = "available"
        #expect(make(Fixtures.snapshot(accounts: accounts)).meters.count == 3)
        accounts[0].availability?.state = "rate_limited"
        #expect(make(Fixtures.snapshot(accounts: accounts)).meters.count == 3)
        #expect(make(Fixtures.snapshot(accounts: nil)).meters.count == 3)
        #expect(
            make(Fixtures.snapshot(accounts: snapshot.accounts, accountsError: "offline")).meters
                .count == 3)
        #expect(make(snapshot, now: Fixtures.now.addingTimeInterval(180)).meters.count == 3)
    }

    @Test("weekly usage counts paused accounts, because their quota is still spent")
    func pausedAccountsStillCount() {
        var accounts = Fixtures.accounts()
        for index in accounts.indices where accounts[index].provider == "anthropic" {
            accounts[index].availability?.state = "paused"
        }
        let panel = make(Fixtures.snapshot(accounts: accounts), display: .usage)
        #expect(panel.usageRows.map(\.label) == ["GPT", "Claude", "Fable"])
        #expect(panel.usageRows[1].accountCount == 2)
        #expect(panel.meters.isEmpty)
    }

    @Test("stacked bars contain only workload pace bars")
    func bars() {
        let panel = make()
        #expect(panel.headline.isEmpty)
        #expect(panel.display == .compact)
        #expect(panel.usageRows.isEmpty)
        #expect(panel.meters.map(\.label) == ["Claude", "GPT", "Fable"])
        #expect(panel.meters[0].signal.fill == -50)
        #expect(panel.severity == .warning)
        #expect(!panel.meters[0].alwaysShowsValue)
        #expect(panel.tooltip.contains("2 available now"))
        #expect(panel.tooltip.contains("2/2 modeled"))
    }

    @Test("weekly usage draws one marked percentage per workload")
    func usage() {
        let panel = make(display: .usage)
        #expect(panel.headline.isEmpty)
        #expect(panel.meters.isEmpty)
        #expect(panel.usageRows.map(\.label) == ["GPT", "Claude", "Fable"])
        #expect(panel.usageRows.map(\.mark) == [.openai, .anthropic, .fable])
        #expect(panel.usageRows[0].valueText == "62%")
        #expect(panel.usageRows[2].valueText == "0%")
        #expect(panel.severity == .normal)
        #expect(make(display: .usage, showScoped: false).usageRows.count == 2)
    }

    @Test("a server without a fable family shows no fable meter")
    func fableNeedsAWorkload() {
        var payload = Fixtures.workloads()
        payload.workloads?.removeAll { $0.id == "family:fable" }
        let panel = make(Fixtures.snapshot(workloads: payload), display: .usage)
        #expect(panel.usageRows.map(\.id) == ["class:codex", "class:anthropic"])
    }

    @Test("no account list yet reads as loading or failure, never as no accounts")
    func usagePlaceholders() {
        let starting = RefreshSnapshot.loading(baseURL: "http://localhost:8080")
        let loading = PanelContent.make(
            snapshot: starting,
            view: starting.rendered(options: ViewOptions(), now: Fixtures.now),
            display: .usage, showScoped: true, now: Fixtures.now)
        #expect(loading.headline == "Usage …")
        #expect(loading.usageRows.isEmpty)

        let failed = make(
            Fixtures.snapshot(accounts: nil, accountsError: "Connection failed"), display: .usage)
        #expect(failed.headline == "Usage !")
        #expect(failed.usageRows.isEmpty)

        // An account list that loaded and matched nothing is the only "None".
        #expect(make(Fixtures.snapshot(accounts: []), display: .usage).usageRows[0].valueText
            == "None")
    }

    @Test("the usage tooltip keeps every line the pace tooltip carries")
    func usageTooltip() {
        var accounts = Fixtures.accounts()
        accounts[0].measurementState = "stale"
        let snapshot = Fixtures.snapshot(accounts: accounts)
        let usage = make(snapshot, display: .usage)
        let compact = make(snapshot)
        let lines = usage.tooltip.components(separatedBy: "\n")

        #expect(lines.first == "Weekly usage · equal account average")
        #expect(lines.contains("Claude: 62% weekly used · 2/2 accounts · cached"))
        #expect(lines.contains("* Partial or cached readings"))
        for line in compact.tooltip.components(separatedBy: "\n") {
            #expect(usage.tooltip.contains(line), "usage tooltip dropped: \(line)")
        }
        for tooltip in [usage.tooltip, compact.tooltip] {
            #expect(tooltip.contains("assume the current distribution of consumption"))
            #expect(tooltip.contains("fresh, unpinned, nominal-sized requests"))
        }
    }

    @Test("usage freshness follows the accounts reply, not a skewed local clock")
    func accountsClock() {
        // The client clock runs an hour ahead of the server's; the readings are still current.
        let localNow = Fixtures.now.addingTimeInterval(3600)
        let snapshot = Fixtures.snapshot(receivedAt: localNow)
        let panel = make(snapshot, display: .usage, now: localNow)
        #expect(panel.usageRows.allSatisfy { !$0.stale })
        #expect(panel.usageRows[0].valueText == "62%")
    }

    @Test("stale and expired readings always carry visible labels")
    func stale() {
        let panel = make(now: Fixtures.now.addingTimeInterval(180))
        #expect(panel.meters.allSatisfy { $0.alwaysShowsValue })
        #expect(panel.meters.allSatisfy { $0.signal.fill == 0 && $0.signal.value == "Stale" })
        #expect(panel.severity == .unknown)
        var payload = Fixtures.workloads()
        payload.workloads?[0].weekly?.period?.endsAt = Fixtures.timestamp()
        let expired = make(Fixtures.snapshot(workloads: payload))
        #expect(expired.meters[0].alwaysShowsValue)
        #expect(expired.meters[0].signal.value == "Expired")
    }

    @Test("a missing feed stays neutral and visible")
    func missing() {
        let panel = make(Fixtures.snapshot(workloads: nil, workloadsError: "HTTP 404"))
        #expect(panel.headline == "Pace –")
        #expect(panel.severity == .unknown)
        #expect(panel.tooltip.contains("HTTP 404"))
        #expect(panel.meters.isEmpty)
    }
}
