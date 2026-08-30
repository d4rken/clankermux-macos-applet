import AppKit
import ClankermuxCore
import Testing

@testable import ClankermuxUsage

/// Guards the failure mode that a menu bar item is impossible to notice from code alone: it is
/// present, correctly sized, and paints nothing. These render the view offscreen and count the
/// pixels it actually put down.
@MainActor
@Suite("Panel item view")
struct PanelItemViewTests {

    @Test("the icon form paints, and is narrow enough for a busy menu bar")
    func iconFormPaints() {
        let content = panel(display: .icon)
        let view = PanelItemView(content: content, barWidth: 52, showsPercentages: true)

        // Measured on a 1512-point notched display already holding eleven status items: the room
        // left for a new one was 20 points, and macOS drew nothing at all beyond that. The icon has
        // to stay in that neighbourhood or it silently disappears.
        #expect(view.fittingWidth < 40)
        #expect(paintedPixels(view) > 0)
    }

    @Test("the runway form paints and is far wider than the icon")
    func runwayFormPaints() {
        let icon = PanelItemView(content: panel(display: .icon), barWidth: 52, showsPercentages: true)
        let runway = PanelItemView(
            content: panel(display: .runway), barWidth: 52, showsPercentages: true)

        #expect(paintedPixels(runway) > 0)
        // Ordering rather than an absolute width: the runway string grows with the availability and
        // overload markers, so a fixed number would only pin this fixture. Against a live server
        // the same form measured about 106 points, against about 29 for the icon.
        #expect(runway.fittingWidth > icon.fittingWidth * 2)
    }

    @Test("the full form is the widest of the three")
    func fullFormIsWidest() {
        let runway = PanelItemView(
            content: panel(display: .runway), barWidth: 52, showsPercentages: true)
        let full = PanelItemView(content: panel(display: .full), barWidth: 52, showsPercentages: true)

        #expect(paintedPixels(full) > 0)
        #expect(full.fittingWidth > runway.fittingWidth)
    }

    @Test("the loading placeholder paints too, so a starting app is never a blank gap")
    func loadingIconPaints() {
        let content = PanelContent.make(
            state: .notLoaded,
            view: emptyView(),
            lastError: "",
            lastRunwayError: "",
            lastSuccess: nil,
            display: .icon,
            now: Date()
        )
        let view = PanelItemView(content: content, barWidth: 52, showsPercentages: true)
        #expect(paintedPixels(view) > 0)
    }

    // MARK: - Helpers

    private func paintedPixels(_ view: PanelItemView) -> Int {
        view.frame = NSRect(x: 0, y: 0, width: max(1, view.fittingWidth), height: 22)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var painted = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15 {
                painted += 1
            }
        }
        return painted
    }

    private func emptyView() -> UsageView {
        UsageModel.buildView(
            accounts: nil, status: nil, runway: nil, options: ViewOptions(), localNow: Date())
    }

    private func panel(display: PanelDisplay) -> PanelContent {
        let accounts = [
            Account(
                id: "a", name: "Account A", provider: "anthropic", isDefaultCandidate: true,
                availability: Availability(state: "available"),
                measurementState: "fresh",
                windows: [
                    UsageWindow(kind: "five_hour", label: "5-hour", utilizationPct: 5),
                    UsageWindow(kind: "seven_day", label: "Weekly", utilizationPct: 49),
                ])
        ]
        let status = StatusResponse(
            schema: "clankermux.public.status.v1",
            status: "ok",
            pool: PoolInfo(
                configured: 1, configuredPresence: .present,
                defaultRoutable: 1, defaultRoutablePresence: .present),
            usage: UsageSection(
                fiveHour: UsageAggregate(meanUtilizationPct: 5, contributingAccountCount: 1),
                sevenDay: UsageAggregate(meanUtilizationPct: 49, contributingAccountCount: 1))
        )
        // A real runway, so the runway form is measured at a realistic width rather than at the
        // `R –` placeholder a nil runway produces.
        let now = Date()
        let runway = RunwayResponse(
            schema: "clankermux.public.runway.v1",
            generatedAt: FlexibleTimestamp(date: now),
            horizonMs: 14 * 24 * 60 * 60 * 1000,
            coverage: Coverage(activeKeyCount: 2, statedKeyCount: 2, unobservedKeyCount: 0),
            worstStatedOutcome: StatedOutcome(
                kind: "runway",
                exhaustsAt: FlexibleTimestamp(date: now.addingTimeInterval(5 * 24 * 3600 + 18 * 3600))
            )
        )
        let view = UsageModel.buildView(
            accounts: accounts, status: status, runway: runway, options: ViewOptions(),
            localNow: now)
        return PanelContent.make(
            state: .loaded(view.accounts),
            view: view,
            lastError: "",
            lastRunwayError: "",
            lastSuccess: Date(),
            display: display,
            now: Date()
        )
    }
}
