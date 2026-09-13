import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Panel content")
struct PanelContentTests {
    @Test("menu bars hide fully paused providers and their families, then restore them on resume")
    func pausedProviders() {
        var accounts = Fixtures.accounts()
        for index in accounts.indices where accounts[index].provider == "anthropic" {
            accounts[index].availability?.state = "paused"
        }
        let snapshot = Fixtures.snapshot(accounts: accounts)
        for display in [PanelDisplay.compact, .full] {
            let panel = make(snapshot, display: display)
            #expect(panel.meters.map(\.label) == ["GPT"])
            #expect(panel.tooltip.contains("Claude"))
        }
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

    private func make(
        _ snapshot: RefreshSnapshot = Fixtures.snapshot(), display: PanelDisplay = .full,
        now: Date = Fixtures.now
    ) -> PanelContent {
        PanelContent.make(
            snapshot: snapshot, view: snapshot.rendered(options: ViewOptions(), now: now),
            display: display, now: now)
    }

    @Test("full display contains only workload pace bars")
    func bars() {
        let panel = make()
        #expect(panel.headline.isEmpty)
        #expect(panel.meters.map(\.label) == ["Claude", "GPT", "Fable"])
        #expect(panel.meters[0].signal.fill == -50)
        #expect(panel.severity == .warning)
        #expect(!panel.meters[0].alwaysShowsValue)
        #expect(panel.tooltip.contains("2 available now"))
        #expect(panel.tooltip.contains("2/2 modeled"))
    }

    @Test("icon and compact modes preserve the full tooltip")
    func compact() {
        let icon = make(display: .icon)
        let compact = make(display: .compact)
        #expect(icon.iconOnly && icon.headline.isEmpty && icon.meters.isEmpty)
        #expect(compact.headline.isEmpty)
        #expect(compact.compact)
        #expect(compact.meters.map(\.label) == ["Claude", "GPT", "Fable"])
        #expect(icon.tooltip == compact.tooltip)
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
