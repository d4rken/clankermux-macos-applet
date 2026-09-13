import AppKit
import ClankermuxCore

/// Draws the menu bar item: either one directional pace meter per workload, or one weekly usage
/// percentage per provider.
///
/// This is content only. The hosting `NSStatusBarButton` stays the event owner, so clicks,
/// highlighting and accessibility keep working.
@MainActor
final class PanelItemView: NSView {
    typealias MarkProvider = @MainActor (ProviderMark) -> NSImage?

    private static let itemSpacing: CGFloat = 10
    private static let meterSpacing: CGFloat = 4
    private static let barCornerRadius: CGFloat = 4
    private static let horizontalInset: CGFloat = 6
    private static let compactColumnWidth: CGFloat = 52
    private static let compactRows = 3

    private var content: PanelContent
    private let markProvider: MarkProvider

    init(content: PanelContent, markProvider: @escaping MarkProvider = ProviderMarks.image) {
        self.content = content
        self.markProvider = markProvider
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func update(content: PanelContent) {
        guard self.content != content else { return }
        self.content = content
        needsDisplay = true
    }

    /// The width the status item has to reserve. An arbitrary subview's `intrinsicContentSize` does
    /// not reliably drive `NSStatusItem.length`, so the delegate sets it from this.
    var fittingWidth: CGFloat {
        if usesStack {
            let columns = (content.meters.count + Self.compactRows - 1) / Self.compactRows
            return CGFloat(columns) * Self.compactColumnWidth
        }
        let segments = segments()
        let content = segments.reduce(CGFloat(0)) { $0 + $1.leading + $1.width }
        return content + 2 * Self.horizontalInset
    }

    override func draw(_ dirtyRect: NSRect) {
        if usesStack {
            drawCompact()
            return
        }
        var x = Self.horizontalInset
        let midY = bounds.midY
        for segment in segments() {
            x += segment.leading
            switch segment.kind {
            case .text(let string):
                let size = string.size()
                string.draw(at: NSPoint(x: x, y: midY - size.height / 2))
            case .mark(let mark, let fallback):
                draw(mark: mark, fallback: fallback, x: x, midY: midY)
            }
            x += segment.width
        }
    }

    private var usesStack: Bool { content.display == .compact && !content.meters.isEmpty }

    private func drawCompact() {
        for (index, meter) in content.meters.enumerated() {
            let column = index / Self.compactRows
            let row = index % Self.compactRows
            let rows = min(Self.compactRows, content.meters.count - column * Self.compactRows)
            let rowHeight: CGFloat = 7
            let x = CGFloat(column) * Self.compactColumnWidth + 4
            let midY = bounds.midY + (CGFloat(rows - 1) / 2 - CGFloat(row)) * rowHeight
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 6.5, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let label = String(meter.label.prefix(1)).uppercased()
            let labelHeight = (label as NSString).size(withAttributes: attributes).height
            (label as NSString).draw(
                in: NSRect(x: x, y: midY - labelHeight / 2, width: 10, height: labelHeight),
                withAttributes: attributes)
            if meter.alwaysShowsValue {
                var stateAttributes = attributes
                stateAttributes[.foregroundColor] = meter.signal.severity.accentColor
                (meter.signal.value as NSString).draw(
                    in: NSRect(
                        x: x + 12, y: midY - labelHeight / 2, width: 32, height: labelHeight),
                    withAttributes: stateAttributes)
            } else {
                draw(
                    bar: meter.signal.fill, severity: meter.signal.severity,
                    x: x + 12, midY: midY, width: 32, height: 3)
            }
        }
    }

    /// The mark stays label-coloured whatever the reading says: severity is carried by the value
    /// beside it, and a red or green brand mark reads as a claim about the provider.
    private func draw(mark: ProviderMark, fallback: String, x: CGFloat, midY: CGFloat) {
        let side = ProviderMarks.side
        let rect = NSRect(x: x, y: midY - side / 2, width: side, height: side)
        guard let image = markProvider(mark) else {
            let attributed = NSAttributedString(
                string: fallback,
                attributes: [.font: Self.labelFont, .foregroundColor: NSColor.labelColor])
            let size = attributed.size()
            attributed.draw(
                at: NSPoint(x: x + (side - size.width) / 2, y: midY - size.height / 2))
            return
        }
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.draw(in: rect)
            return
        }
        // The layer starts transparent, so the tint clips to the glyph instead of filling the rect
        // over whatever the menu bar already drew there.
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect)
        NSColor.labelColor.set()
        rect.fill(using: .sourceAtop)
        context.endTransparencyLayer()
    }

    private func draw(
        bar percent: Double, severity: Severity, x: CGFloat, midY: CGFloat,
        width: CGFloat, height: CGFloat
    ) {
        let track = NSRect(x: x, y: midY - height / 2, width: width, height: height)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: track, xRadius: Self.barCornerRadius, yRadius: Self.barCornerRadius
        ).fill()

        let half = width / 2
        if percent != 0 {
            let width = max(2, half * CGFloat(min(100, abs(percent))) / 100)
            let fill = NSRect(
                x: percent < 0 ? track.midX - width : track.midX,
                y: track.minY, width: width, height: track.height)
            severity.accentColor.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
        }
        NSColor.labelColor.withAlphaComponent(0.65).setFill()
        NSRect(x: track.midX - 0.5, y: track.minY - 1, width: 1, height: track.height + 2).fill()
    }

    // MARK: - Layout

    private struct Segment {
        enum Kind {
            case text(NSAttributedString)
            case mark(ProviderMark, fallback: String)
        }

        let kind: Kind
        let width: CGFloat
        let leading: CGFloat
    }

    private func segments() -> [Segment] {
        var segments: [Segment] = []
        if !content.headline.isEmpty {
            segments.append(
                text(
                    content.headline, font: Self.headlineFont,
                    color: content.severity.accentColor, leading: 0))
        }

        for row in content.usageRows {
            segments.append(
                Segment(
                    kind: .mark(row.mark, fallback: String(row.label.prefix(1)).uppercased()),
                    width: ProviderMarks.side,
                    leading: segments.isEmpty ? 0 : Self.itemSpacing))
            segments.append(
                text(
                    row.valueText, font: Self.percentFont, color: row.severity.accentColor,
                    leading: Self.meterSpacing))
        }
        return segments
    }

    private func text(_ string: String, font: NSFont, color: NSColor, leading: CGFloat) -> Segment {
        let attributed = NSAttributedString(
            string: string, attributes: [.font: font, .foregroundColor: color])
        return Segment(kind: .text(attributed), width: attributed.size().width, leading: leading)
    }

    private static var baseFontSize: CGFloat { NSFont.menuBarFont(ofSize: 0).pointSize }
    private static var headlineFont: NSFont { .systemFont(ofSize: baseFontSize, weight: .semibold) }
    private static var labelFont: NSFont {
        .systemFont(ofSize: baseFontSize * 0.88, weight: .semibold)
    }
    private static var percentFont: NSFont {
        .systemFont(ofSize: baseFontSize * 0.82, weight: .regular)
    }
}
