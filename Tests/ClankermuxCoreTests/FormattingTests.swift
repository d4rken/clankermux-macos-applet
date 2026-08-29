import Foundation
import Testing

@testable import ClankermuxCore

@Suite("Formatting")
struct FormattingTests {
    @Test("compact duration ladder")
    func durationLadder() {
        #expect(Formatting.formatDuration(0) == "<1m")
        #expect(Formatting.formatDuration(29_000) == "<1m")
        #expect(Formatting.formatDuration(30_000) == "1m")
        #expect(Formatting.formatDuration(45 * 60_000) == "45m")
        #expect(Formatting.formatDuration(59 * 60_000) == "59m")
        #expect(Formatting.formatDuration(60 * 60_000) == "1h")
        #expect(Formatting.formatDuration(90 * 60_000) == "1h 30m")
        #expect(Formatting.formatDuration(23 * 3_600_000) == "23h")
        #expect(Formatting.formatDuration(24 * 3_600_000) == "1d")
        #expect(Formatting.formatDuration(26 * 3_600_000) == "1d 2h")
        #expect(Formatting.formatDuration(14 * 24 * 3_600_000) == "14d")
    }

    /// `horizonMs`, `ageMs` and the reset countdowns come off the wire, where any finite number
    /// passes schema validation, including magnitudes that no `Int` can hold.
    @Test("an out-of-range duration saturates instead of trapping")
    func outOfRangeDuration() {
        #expect(
            Formatting.formatDuration(1e300)
                == Formatting.formatDuration(.greatestFiniteMagnitude))
        #expect(Formatting.formatDuration(-1e300) == "<1m")
    }

    @Test("timestamps render as local wall-clock time")
    func timestampPattern() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 24
        components.hour = 13
        components.minute = 5
        components.second = 9
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let instant = calendar.date(from: components)!

        #expect(Formatting.formatTimestamp(instant) == "2026-08-24 13:05:09")
        #expect(Formatting.formatTimestamp(nil) == "")
    }

    /// 2025-12-29 falls in week 1 of the 2026 week-numbering year, so a `YYYY` pattern would render
    /// it as 2026.
    @Test("the year is the calendar year, not the week-numbering year")
    func calendarYearAroundNewYear() {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 29
        components.hour = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let instant = calendar.date(from: components)!

        #expect(Formatting.formatTimestamp(instant).hasPrefix("2025-12-29"))
    }

    @Test("reset countdowns and the reset-due boundary")
    func resetCountdowns() {
        let now = Fixtures.now
        #expect(
            Formatting.formatReset(Fixtures.date("2026-08-24T12:45:00.000Z"), now: now) == "in 45m")
        #expect(
            Formatting.formatReset(Fixtures.date("2026-08-25T14:00:00.000Z"), now: now)
                == "in 1d 2h")
        #expect(Formatting.formatReset(nil, now: now) == "")
        #expect(Formatting.formatReset(now, now: now) == "reset due")
        #expect(Formatting.formatReset(now.addingTimeInterval(-1), now: now) == "reset due")
        #expect(Formatting.formatReset(now.addingTimeInterval(1), now: now) == "in <1m")
    }

    @Test("configured server URLs are normalized")
    func normalizesBaseUrls() {
        #expect(
            Formatting.normalizeBaseUrl(" proxy.example.test:8080/ ")
                == "http://proxy.example.test:8080")
        #expect(Formatting.normalizeBaseUrl("https://example.test///") == "https://example.test")
        #expect(Formatting.normalizeBaseUrl("") == "")
        #expect(Formatting.normalizeBaseUrl(nil) == "")
        #expect(Formatting.normalizeBaseUrl("   ") == "")
        #expect(Formatting.normalizeBaseUrl("HTTP://Example.test/") == "HTTP://Example.test")
    }

    @Test("wire enums are humanized")
    func humanizesStatuses() {
        #expect(Formatting.humanizeStatus("rate_limited") == "Rate limited")
        #expect(Formatting.humanizeStatus("queueing") == "Queueing")
        #expect(Formatting.humanizeStatus("") == "Unknown")
        #expect(Formatting.humanizeStatus(nil) == "Unknown")
        #expect(Formatting.humanizeStatus("  _ ") == "Unknown")
    }

    @Test("the server clock advances from the local receive instant")
    func anchoredNowUnderSkew() {
        let now = Fixtures.now
        let anchored = Formatting.anchoredNow(
            generatedAt: now,
            receivedAt: now.addingTimeInterval(1),
            localNow: now.addingTimeInterval(61)
        )
        #expect(anchored == now.addingTimeInterval(60))
    }

    @Test("a missing anchor falls back to local time")
    func anchoredNowWithoutAnchor() {
        let now = Fixtures.now
        #expect(
            Formatting.anchoredNow(generatedAt: nil, receivedAt: now, localNow: now) == now)
        #expect(
            Formatting.anchoredNow(generatedAt: now, receivedAt: nil, localNow: now) == now)
    }
}

@Suite("Percent")
struct PercentTests {
    @Test("missing utilization does not become zero usage")
    func missingIsNotZero() {
        #expect(Percent.clampPercent(nil) == nil)
        #expect(Percent.clampPercent(0) == 0)
        #expect(Percent.clampPercent(Double.nan) == nil)
        #expect(Percent.clampPercent(Double.infinity) == nil)
    }

    @Test("readings are clamped and rounded")
    func clampsAndRounds() {
        #expect(Percent.clampPercent(37.5) == 38)
        #expect(Percent.clampPercent(70.3) == 70)
        #expect(Percent.clampPercent(-5) == 0)
        #expect(Percent.clampPercent(140) == 100)
        #expect(Percent.clampNumber(140) == 100)
        #expect(Percent.clampNumber(37.5) == 37.5)
    }
}
