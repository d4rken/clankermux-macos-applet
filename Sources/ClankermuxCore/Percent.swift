import Foundation

/// Percentage clamping shared by every usage reading.
///
/// The nil/zero distinction is load-bearing: a window whose `utilizationPct` is absent must be
/// dropped, never shown as 0%.
///
///     clampPercent(nil) == nil
///     clampPercent(0)   == 0
public enum Percent {
    /// Clamps a raw reading into `0...100`, treating absent and non-finite values as unreadable.
    public static func clampNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, min(100, value))
    }

    /// `clampNumber` rounded to a whole percentage point.
    public static func clampPercent(_ value: Double?) -> Int? {
        guard let number = clampNumber(value) else { return nil }
        return Int(number.rounded())
    }
}
