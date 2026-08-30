import CoreGraphics

/// Fixed sizes for the popover.
///
/// The height cap is derived from the screen rather than hardcoded, so the popover scrolls only
/// when the content genuinely will not fit the display, not at an arbitrary threshold.
enum PopoverMetrics {
    static let width: CGFloat = 420

    /// Never collapse to an unusable sliver, however small the reported screen.
    static let minimumHeight: CGFloat = 220

    /// Room for the popover's arrow, the menu bar it hangs from, and a little breathing space.
    static let screenMargin: CGFloat = 32

    static func maxHeight(screenVisibleHeight: CGFloat) -> CGFloat {
        max(minimumHeight, screenVisibleHeight - screenMargin)
    }
}
