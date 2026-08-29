import Foundation

/// A server-reported `Double` narrowed to `Int`, saturating at the integer bounds.
///
///     clampedInt(1e300) == Int.max
///     clampedInt(-1e300) == Int.min
///     clampedInt(.nan) == 0
///
/// `Int(_:)` traps on any finite value beyond the integer range, and these magnitudes arrive
/// straight off the wire, so an absurd count would abort the app on every refresh.
func clampedInt(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    if value >= Double(Int.max) { return .max }
    if value <= Double(Int.min) { return .min }
    return Int(value)
}

/// Compact, locale-independent renderings of the durations, instants and status strings that the
/// panel and popup display.
public enum Formatting {
    /// Compact duration ladder.
    ///
    ///     30_000      -> "<1m"
    ///     45 * 60_000 -> "45m"
    ///     26 hours    -> "1d 2h"
    ///
    /// Minutes are rounded; hours and days are floored.
    public static func formatDuration(_ milliseconds: Double) -> String {
        guard milliseconds.isFinite else { return "<1m" }
        var minutes = clampedInt(max(0, (milliseconds / 60_000).rounded()))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        minutes %= 60
        if hours < 24 {
            return minutes != 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours != 0 ? "\(days)d \(remainingHours)h" : "\(days)d"
    }

    /// Local wall-clock rendering of an instant, empty for an unreadable one.
    ///
    /// The pattern uses lowercase `yyyy` (calendar year). Uppercase `YYYY` is the week-numbering
    /// year and reports the wrong year in the days around New Year.
    public static func formatTimestamp(_ instant: Date?) -> String {
        guard let instant else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: instant)
    }

    /// Countdown to a reset instant: empty when unknown, `reset due` once it has passed.
    public static func formatReset(_ instant: Date?, now: Date) -> String {
        guard let instant else { return "" }
        if instant <= now { return "reset due" }
        return "in \(formatDuration(instant.timeIntervalSince(now) * 1000))"
    }

    /// Turns a wire enum such as `rate_limited` into `Rate limited`.
    public static func humanizeStatus(_ value: String?) -> String {
        let text = (value ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Unknown" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The server's clock advanced by the local time elapsed since its reply was received.
    ///
    /// Countdowns stay correct when the client clock is skewed against the server's. Falls back to
    /// local time when either anchor is missing.
    public static func anchoredNow(generatedAt: Date?, receivedAt: Date?, localNow: Date) -> Date {
        guard let generatedAt, let receivedAt else { return localNow }
        return generatedAt.addingTimeInterval(max(0, localNow.timeIntervalSince(receivedAt)))
    }

    /// Trims, defaults a missing scheme to `http://`, and drops trailing slashes.
    ///
    ///     " proxy.example.test:8080/ " -> "http://proxy.example.test:8080"
    ///     "https://example.test///"    -> "https://example.test"
    public static func normalizeBaseUrl(_ value: String?) -> String {
        var url = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return "" }
        if url.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) == nil {
            url = "http://\(url)"
        }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
