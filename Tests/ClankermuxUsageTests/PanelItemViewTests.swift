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
    @Test("render compact bars for visual inspection when requested")
    func compactPreview() throws {
        guard let directory = ProcessInfo.processInfo.environment["CLANKERMUX_PREVIEW_DIR"] else {
            return
        }
        let view = PanelItemView(
            content: panel(display: .compact), barWidth: 52, showsPercentages: false)
        view.appearance = NSAppearance(named: .aqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        view.frame = NSRect(x: 0, y: 0, width: view.fittingWidth, height: 22)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("compact-bars.png"))
    }

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

    @Test("three compact bars stack in a single narrow column")
    func compactFormPaints() {
        let icon = PanelItemView(
            content: panel(display: .icon), barWidth: 52, showsPercentages: true)
        let compact = PanelItemView(
            content: panel(display: .compact), barWidth: 52, showsPercentages: true)

        #expect(paintedPixels(compact) > 0)
        #expect(compact.fittingWidth == 52)
        #expect(compact.fittingWidth < icon.fittingWidth * 2)
    }

    @Test("pace bars paint at their configured width")
    func fullFormIsWidest() {
        let full = PanelItemView(
            content: panel(display: .full), barWidth: 52, showsPercentages: true)

        #expect(paintedPixels(full) > 0)
        #expect(full.fittingWidth > 200)
    }

    @Test("the loading placeholder paints too, so a starting app is never a blank gap")
    func loadingIconPaints() {
        let snapshot = RefreshSnapshot.loading(baseURL: "")
        let content = PanelContent.make(
            snapshot: snapshot, view: snapshot.rendered(options: ViewOptions(), now: Date()),
            display: .icon, now: Date())
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
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15
            {
                painted += 1
            }
        }
        return painted
    }

    private func panel(display: PanelDisplay) -> PanelContent {
        let snapshot = UIFixtures.snapshot()
        return PanelContent.make(
            snapshot: snapshot, view: snapshot.rendered(options: ViewOptions(), now: Date()),
            display: display, now: Date())
    }
}
