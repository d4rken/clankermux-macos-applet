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
    @Test("render the workload popover for visual inspection when requested")
    func preview() throws {
        guard let directory = ProcessInfo.processInfo.environment["CLANKERMUX_PREVIEW_DIR"] else {
            return
        }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", .dark)] {
            let model = PopoverModel(
                content: detail(accounts: 4), isRefreshing: false,
                canOpenDashboard: true, maxContentHeight: 2000)
            let content = PopoverView(
                model: model, onRefresh: {}, onOpenDashboard: {}, onOpenSettings: {}, onQuit: {}
            )
            .environment(\.colorScheme, scheme)
            .background(scheme == .light ? Color.white : Color(white: 0.12))
            let host = NSHostingView(rootView: content)
            host.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.frame.size = host.fittingSize
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("popover-\(name).png"))
        }
    }

    @Test("a four-account popover respects the laptop height cap including its footer")
    func fitsALaptopScreen() {
        let size = fittingSize(accounts: 4)

        #expect(size.height < 550)
        #expect(size.width == 620)
    }

    @Test("a six-account popover, the shape of a real server, still fits a laptop screen")
    func realisticSixAccountsFit() {
        let size = fittingSize(accounts: 6)
        // The cap on a 14-inch MacBook Pro is 912 points: 944 visible, less room for the arrow.
        #expect(size.height < 700)
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

    @Test("content that fits builds no scroll view, so no scroller can be drawn")
    func fittingContentHasNoScrollView() {
        // macOS draws a persistent scroller whenever a mouse is attached, so a ScrollView that is
        // never scrolled still shows a bar. Not building one is the only way to be sure.
        let host = hosted(accounts: 2, maxHeight: 4000)
        #expect(!containsScrollView(host))
    }

    @Test("content that overflows does build a scroll view")
    func overflowingContentScrolls() {
        let host = hosted(accounts: 6, maxHeight: 200)
        #expect(containsScrollView(host))
    }

    // MARK: - Helpers

    private func containsScrollView(_ view: NSView) -> Bool {
        if view is NSScrollView { return true }
        return view.subviews.contains(where: containsScrollView)
    }

    @discardableResult
    private func hosted(accounts count: Int, maxHeight: CGFloat) -> NSHostingView<PopoverView> {
        let model = PopoverModel(
            content: detail(accounts: count), isRefreshing: false, canOpenDashboard: true,
            maxContentHeight: maxHeight)
        let host = NSHostingView(
            rootView: PopoverView(
                model: model, onRefresh: {}, onOpenDashboard: {}, onOpenSettings: {}, onQuit: {}))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: maxHeight)
        host.layoutSubtreeIfNeeded()
        // The scroll decision runs on a preference update, so let the run loop deliver it.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return host
    }

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
        let snapshot = UIFixtures.snapshot(accounts: count)
        return DetailContent.make(
            snapshot: snapshot, view: snapshot.rendered(options: ViewOptions(), now: Date()),
            now: Date())
    }
}
