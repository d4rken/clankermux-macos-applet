import AppKit
import ClankermuxCore

/// Draws the menu bar item: the runway headline followed by one meter per panel pool.
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
        self.content = content
        self.barWidth = barWidth
        self.showsPercentages = showsPercentages
        needsDisplay = true
    }

    /// The width the status item has to reserve. An arbitrary subview's `intrinsicContentSize` does
    /// not reliably drive `NSStatusItem.length`, so the delegate sets it from this.
    var fittingWidth: CGFloat {
        let segments = segments()
        let content = segments.reduce(CGFloat(0)) { $0 + $1.leading + $1.width }
        return content + 2 * Self.horizontalInset
    }

    override func draw(_ dirtyRect: NSRect) {
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

    private func draw(iconAt x: CGFloat, midY: CGFloat) {
        let color =
            content.runwayIsMuted ? NSColor.secondaryLabelColor : content.runwaySeverity.accentColor
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

    private func draw(bar percent: Int, severity: Severity, x: CGFloat, midY: CGFloat) {
        let track = NSRect(
            x: x, y: midY - Self.barHeight / 2, width: barWidth, height: Self.barHeight)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(
            roundedRect: track, xRadius: Self.barCornerRadius, yRadius: Self.barCornerRadius
        ).fill()

        guard percent > 0 else { return }
        let fillWidth = max(2, (barWidth * CGFloat(percent) / 100).rounded())
        let fill = NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height)
        severity.accentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: Self.barCornerRadius, yRadius: Self.barCornerRadius)
            .fill()
    }

    // MARK: - Layout

    private struct Segment {
        enum Kind {
            case text(NSAttributedString)
            case bar(percent: Int, severity: Severity)
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
        let runwayColor =
            content.runwayIsMuted ? NSColor.secondaryLabelColor : content.runwaySeverity.accentColor
        segments.append(text(content.runwayText, font: Self.runwayFont, color: runwayColor, leading: 0))

        if content.showsEmptyPlaceholder {
            segments.append(
                text(
                    "quota –", font: Self.labelFont, color: .secondaryLabelColor,
                    leading: Self.itemSpacing))
        }

        for meter in content.meters {
            segments.append(
                text(
                    meter.label, font: Self.labelFont, color: .labelColor,
                    leading: Self.itemSpacing))
            segments.append(
                Segment(
                    kind: .bar(percent: meter.percent, severity: meter.severity),
                    width: barWidth,
                    leading: Self.meterSpacing
                ))
            if showsPercentages {
                segments.append(
                    text(
                        "\(meter.percent)%", font: Self.percentFont,
                        color: meter.severity.accentColor,
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
    private static var runwayFont: NSFont { .systemFont(ofSize: baseFontSize, weight: .semibold) }
    private static var labelFont: NSFont {
        .systemFont(ofSize: baseFontSize * 0.88, weight: .semibold)
    }
    private static var percentFont: NSFont {
        .systemFont(ofSize: baseFontSize * 0.82, weight: .regular)
    }
}
