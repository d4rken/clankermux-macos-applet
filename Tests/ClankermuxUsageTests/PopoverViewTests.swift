import AppKit
import ClankermuxCore
import SwiftUI
import Testing

@testable import ClankermuxUsage

/// The popover has no automated runtime lane, so its size is measured here instead of eyeballed:
/// the view is laid out offscreen and its fitting size read back. That keeps the compactness claim
/// and the fit-the-screen rule honest.
@MainActor
@Suite("Popover view")
struct PopoverViewTests {

    @Test("a four-account popover fits a laptop screen without scrolling")
    func fitsALaptopScreen() {
        let size = fittingSize(accounts: 4)

        // A 14-inch MacBook Pro has 982 points of height, less the menu bar. If four accounts do
        // not fit that, the common case is scrolling, which is what this redesign set out to stop.
        #expect(size.height < 900)
        #expect(size.width <= 460)
    }

    @Test("the popover grows with account count rather than clipping")
    func growsWithContent() {
        let small = fittingSize(accounts: 1)
        let large = fittingSize(accounts: 6)
        #expect(large.height > small.height)
    }

    @Test("the height cap follows the screen, so scrolling starts only past it")
    func heightCapFollowsScreen() {
        // A roomy screen caps well above a laptop's content height.
        #expect(PopoverMetrics.maxHeight(screenVisibleHeight: 1400) > 1200)
        // A short screen still caps below its own height, leaving room for the arrow and margins.
        #expect(PopoverMetrics.maxHeight(screenVisibleHeight: 600) < 600)
        // Absurd input cannot produce a degenerate popover.
        #expect(PopoverMetrics.maxHeight(screenVisibleHeight: 0) >= PopoverMetrics.minimumHeight)
    }

    // MARK: - Helpers

    private func fittingSize(accounts count: Int) -> CGSize {
        let model = PopoverModel(
            content: detail(accounts: count), isRefreshing: false, canOpenDashboard: true)
        let host = NSHostingView(
            rootView: PopoverView(
                model: model, onRefresh: {}, onOpenDashboard: {}, onOpenSettings: {}, onQuit: {}))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private func detail(accounts count: Int) -> DetailContent {
        let now = Date()

        func window(_ kind: String, _ label: String, _ pct: Double, _ resetIn: Double) -> UsageWindow
        {
            UsageWindow(
                kind: kind, label: label, utilizationPct: pct,
                observedAt: FlexibleTimestamp(date: now),
                resetsAt: FlexibleTimestamp(date: now.addingTimeInterval(resetIn)))
        }

        let accounts = (1...max(1, count)).map { index in
            Account(
                id: "a\(index)", name: "Account \(index)",
                provider: index > 2 ? "codex" : "anthropic",
                isDefaultCandidate: index == 1,
                availability: Availability(state: "available"),
                credential: Credential(state: "valid"),
                measurementState: "fresh",
                windows: [
                    window("five_hour", "5-hour", 5, 3600),
                    window("seven_day", "Weekly", 49, 200_000),
                    window("weekly_scoped", "Fable", 67, 200_000),
                ])
        }

        let status = StatusResponse(
            schema: "clankermux.public.status.v1", generatedAt: FlexibleTimestamp(date: now),
            status: "ok",
            pool: PoolInfo(
                configured: Double(accounts.count), configuredPresence: .present,
                defaultRoutable: Double(accounts.count), defaultRoutablePresence: .present),
            usage: UsageSection(
                fiveHour: UsageAggregate(
                    meanUtilizationPct: 5, contributingAccountCount: Double(accounts.count),
                    earliestResetsAt: FlexibleTimestamp(date: now.addingTimeInterval(3600))),
                sevenDay: UsageAggregate(
                    meanUtilizationPct: 49, contributingAccountCount: Double(accounts.count),
                    earliestResetsAt: FlexibleTimestamp(date: now.addingTimeInterval(200_000)))))

        let runway = RunwayResponse(
            schema: "clankermux.public.runway.v1", generatedAt: FlexibleTimestamp(date: now),
            horizonMs: 14 * 24 * 3600 * 1000,
            coverage: Coverage(activeKeyCount: 2, statedKeyCount: 2, unobservedKeyCount: 0),
            worstStatedOutcome: StatedOutcome(
                kind: "runway",
                exhaustsAt: FlexibleTimestamp(date: now.addingTimeInterval(5 * 24 * 3600))))

        let view = UsageModel.buildView(
            accounts: accounts, status: status, runway: runway, options: ViewOptions(),
            localNow: now)
        return DetailContent.make(
            state: .loaded(view.accounts), view: view, baseURL: "http://127.0.0.1:8080",
            lastError: "", lastRunwayError: "", lastSuccess: now, now: now)
    }
}
