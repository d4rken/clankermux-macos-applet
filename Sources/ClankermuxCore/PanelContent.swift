import Foundation

public struct PanelMeter: Sendable, Equatable, Identifiable {
    public let key: String
    public let label: String
    public let percent: Int
    public let severity: Severity

    public var id: String { key }
}

/// Everything the menu bar item draws, decided without touching AppKit.
public struct PanelContent: Sendable, Equatable {
    /// For example `R 5d 18h · 3/4! ⏳`.
    public let runwayText: String
    public let runwaySeverity: Severity
    /// True while the item is a placeholder, which draws in the neutral label colour rather than a
    /// severity colour.
    public let runwayIsMuted: Bool
    public let meters: [PanelMeter]
    /// `quota –` stands in when no pool is readable.
    public let showsEmptyPlaceholder: Bool
    public let tooltip: String

    public static func make(
        state: LoadState,
        view: UsageView,
        lastError: String,
        lastRunwayError: String,
        lastSuccess: Date?,
        now: Date
    ) -> PanelContent {
        guard state.isLoaded else {
            let failed = !lastError.isEmpty
            return PanelContent(
                runwayText: failed ? "Clankermux !" : "Clankermux …",
                runwaySeverity: failed ? .warning : .normal,
                runwayIsMuted: !failed,
                meters: [],
                showsEmptyPlaceholder: false,
                tooltip: failed ? lastError : "Loading Clankermux usage…"
            )
        }

        let degraded = view.pool.defaultRoutable < view.pool.configured
        let availabilityMarker =
            degraded ? " · \(view.pool.defaultRoutable)/\(view.pool.configured)!" : ""
        let overloadMarker = view.providerOverloads.isEmpty ? "" : " ⏳"

        // Runway describes quota capacity only, so availability and overload trouble has to raise
        // the headline severity separately.
        var severity = view.runway.severity
        if view.pool.defaultRoutable == 0 {
            severity = .critical
        } else if (degraded || !view.providerOverloads.isEmpty) && severity == .normal {
            severity = .warning
        }

        let meters = UsageModel.panelUsagePools(view.usagePools).map {
            PanelMeter(key: $0.key, label: $0.label, percent: $0.usedPercent, severity: $0.severity)
        }

        return PanelContent(
            runwayText: "\(view.runway.panelText)\(availabilityMarker)\(overloadMarker)",
            runwaySeverity: severity,
            runwayIsMuted: false,
            meters: meters,
            showsEmptyPlaceholder: meters.isEmpty,
            tooltip: tooltipLines(
                view: view, lastError: lastError, lastRunwayError: lastRunwayError,
                lastSuccess: lastSuccess, now: now
            ).joined(separator: "\n")
        )
    }

    static func tooltipLines(
        view: UsageView,
        lastError: String,
        lastRunwayError: String,
        lastSuccess: Date?,
        now: Date
    ) -> [String] {
        var lines = [
            "Quota runway: \(view.runway.value)",
            view.runway.summary,
            "Coverage: \(view.runway.coverageText)",
            "Availability: \(view.pool.defaultRoutable) of \(view.pool.configured) accounts in the default routing context",
        ]
        for overload in view.providerOverloads {
            let scope = overload.providerWide ? "provider-wide" : "provider or model scope"
            let retry: String
            if let until = overload.until {
                retry = " · retry \(Formatting.formatReset(until, now: view.now))"
            } else {
                retry = overload.probeActive ? " · recovery probe active" : ""
            }
            lines.append("\(overload.provider) \(scope) overload \(overload.state)\(retry)")
        }
        for pool in view.usagePools {
            let unknown = pool.unknownCount != 0 ? " · \(pool.unknownCount) unknown" : ""
            lines.append(
                "\(pool.label): \(pool.usedPercent)% mean usage across \(pool.accountCount) accounts\(unknown)"
            )
        }
        if !lastRunwayError.isEmpty {
            lines.append("Last runway refresh failed: \(lastRunwayError)")
        }
        if !lastError.isEmpty {
            lines.append("Last refresh failed: \(lastError)")
        } else if let lastSuccess {
            lines.append(
                "Updated \(Formatting.formatDuration(now.timeIntervalSince(lastSuccess) * 1000)) ago"
            )
        }
        return lines
    }
}
