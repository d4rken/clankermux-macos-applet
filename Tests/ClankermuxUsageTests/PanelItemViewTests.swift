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
    @Test("render both menu bar forms for visual inspection when requested")
    func previews() throws {
        guard let directory = ProcessInfo.processInfo.environment["CLANKERMUX_PREVIEW_DIR"] else {
            return
        }
        for (name, appearance, background) in [
            ("light", NSAppearance.Name.aqua, NSColor.white),
            ("dark", NSAppearance.Name.darkAqua, NSColor(white: 0.12, alpha: 1)),
        ] {
            for display in PanelDisplay.allCases {
                try write(
                    PanelItemView(content: panel(display: display)),
                    appearance: appearance, background: background,
                    to: directory, named: "panel-\(display.rawValue)-\(name)")
            }
            try write(
                PanelItemView(content: panel(display: .usage), markProvider: { _ in nil }),
                appearance: appearance, background: background,
                to: directory, named: "panel-usage-fallback-\(name)")
        }
    }

    @Test("three stacked bars fit a single narrow column")
    func compactFormPaints() {
        let compact = PanelItemView(content: panel(display: .compact))

        #expect(paintedPixels(compact) > 0)
        #expect(compact.fittingWidth == 52)
    }

    @Test("weekly usage paints a mark and a percentage per workload, and stays menu-bar sized")
    func usageFormPaints() {
        let usage = PanelItemView(content: panel(display: .usage))

        #expect(paintedPixels(usage) > 0)
        #expect(usage.fittingWidth > PanelItemView(content: panel(display: .compact)).fittingWidth)
        // Three marks, three percentages and their spacing, and nothing beyond that.
        #expect(usage.fittingWidth < 240)
    }

    @Test("a mark the system cannot decode falls back to the workload initial")
    func missingMarkFallsBackToALetter() {
        let content = panel(display: .usage)
        let drawn = PanelItemView(content: content)
        let fallback = PanelItemView(content: content, markProvider: { _ in nil })

        #expect(paintedPixels(fallback) > 0)
        // A letter is narrower than the 16-point mark it replaces, but the row still reserves it.
        #expect(fallback.fittingWidth == drawn.fittingWidth)
    }

    @Test("the loading placeholder paints too, so a starting app is never a blank gap")
    func loadingPlaceholderPaints() {
        let snapshot = RefreshSnapshot.loading(baseURL: "")
        for display in PanelDisplay.allCases {
            let content = PanelContent.make(
                snapshot: snapshot, view: snapshot.rendered(options: ViewOptions(), now: Date()),
                display: display, showScoped: true, now: Date())
            #expect(!content.headline.isEmpty)
            #expect(paintedPixels(PanelItemView(content: content)) > 0)
        }
    }

    // MARK: - Helpers

    private func write(
        _ view: PanelItemView, appearance: NSAppearance.Name, background: NSColor,
        to directory: String, named name: String
    ) throws {
        view.appearance = NSAppearance(named: appearance)
        view.wantsLayer = true
        view.layer?.backgroundColor = background.cgColor
        view.frame = NSRect(x: 0, y: 0, width: max(1, view.fittingWidth), height: 22)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

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
            display: display, showScoped: true, now: Date())
    }
}
