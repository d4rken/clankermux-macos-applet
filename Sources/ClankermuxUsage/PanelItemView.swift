import AppKit
import ClankermuxCore

/// Draws the menu bar item: one directional pace meter per workload.
///
/// This is content only. The hosting `NSStatusBarButton` stays the event owner, so clicks,
/// highlighting and accessibility keep working.
@MainActor
final class PanelItemView: NSView {
    private static let itemSpacing: CGFloat = 10
    private static let meterSpacing: CGFloat = 4
    private static let barHeight: CGFloat = 8
    private static let barCornerRadius: CGFloat = 4
    private static let horizontalInset: CGFloat = 6
    private static let iconSide: CGFloat = 15
    private static let compactColumnWidth: CGFloat = 52
    private static let compactRows = 3

    private var content: PanelContent
    private var barWidth: CGFloat
    private var showsPercentages: Bool

    init(content: PanelContent, barWidth: CGFloat, showsPercentages: Bool) {
        self.content = content
        self.barWidth = barWidth
        self.showsPercentages = showsPercentages
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func update(content: PanelContent, barWidth: CGFloat, showsPercentages: Bool) {
        guard
            self.content != content || self.barWidth != barWidth
                || self.showsPercentages != showsPercentages
        else { return }
        self.content = content
        self.barWidth = barWidth
        self.showsPercentages = showsPercentages
        needsDisplay = true
    }

    /// The width the status item has to reserve. An arbitrary subview's `intrinsicContentSize` does
    /// not reliably drive `NSStatusItem.length`, so the delegate sets it from this.
    var fittingWidth: CGFloat {
        if content.compact && !content.meters.isEmpty {
            let columns = (content.meters.count + Self.compactRows - 1) / Self.compactRows
            return CGFloat(columns) * Self.compactColumnWidth
        }
        let segments = segments()
        let content = segments.reduce(CGFloat(0)) { $0 + $1.leading + $1.width }
        return content + 2 * Self.horizontalInset
    }

    override func draw(_ dirtyRect: NSRect) {
        if content.compact && !content.meters.isEmpty {
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
            case .bar(let percent, let severity):
                draw(bar: percent, severity: severity, x: x, midY: midY)
            case .icon:
                draw(iconAt: x, midY: midY)
            }
            x += segment.width
        }
    }

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

    private func draw(iconAt x: CGFloat, midY: CGFloat) {
        let color =
            content.severity.accentColor
        let rect = NSRect(
            x: x, y: midY - Self.iconSide / 2, width: Self.iconSide, height: Self.iconSide)
        guard let image = Self.icon else {
            // No symbol available: fall back to a filled dot so the item is never blank.
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return
        }
        let tinted = image.copy() as! NSImage
        tinted.isTemplate = true
        tinted.size = NSSize(width: Self.iconSide, height: Self.iconSide)
        tinted.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
    }

    private func draw(
        bar percent: Double, severity: Severity, x: CGFloat, midY: CGFloat,
        width: CGFloat? = nil, height: CGFloat = PanelItemView.barHeight
    ) {
        let barWidth = width ?? self.barWidth
        let track = NSRect(
            x: x, y: midY - height / 2, width: barWidth, height: height)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: track, xRadius: Self.barCornerRadius, yRadius: Self.barCornerRadius
        ).fill()

        let half = barWidth / 2
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
            case bar(percent: Double, severity: Severity)
            case icon
        }

        let kind: Kind
        let width: CGFloat
        let leading: CGFloat
    }

    /// The symbol drawn in icon mode. The first name the running system knows wins, so the view
    /// degrades on older systems instead of drawing nothing.
    private static let iconCandidates = ["gauge", "speedometer", "chart.bar.fill"]

    private static var icon: NSImage? {
        for name in iconCandidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Clankermux") {
                return image
            }
        }
        return nil
    }

    private func segments() -> [Segment] {
        if content.iconOnly {
            return [Segment(kind: .icon, width: Self.iconSide, leading: 0)]
        }
        var segments: [Segment] = []
        let headlineColor =
            content.severity.accentColor
        if !content.headline.isEmpty {
            segments.append(
                text(content.headline, font: Self.headlineFont, color: headlineColor, leading: 0))
        }

        for meter in content.meters {
            segments.append(
                text(
                    meter.label, font: Self.labelFont, color: .labelColor,
                    leading: segments.isEmpty ? 0 : Self.itemSpacing))
            segments.append(
                Segment(
                    kind: .bar(percent: meter.signal.fill, severity: meter.signal.severity),
                    width: barWidth,
                    leading: Self.meterSpacing
                ))
            if meter.alwaysShowsValue || showsPercentages && meter.signal.numeric {
                segments.append(
                    text(
                        meter.signal.value, font: Self.percentFont,
                        color: meter.signal.severity.accentColor,
                        leading: Self.meterSpacing))
            }
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
