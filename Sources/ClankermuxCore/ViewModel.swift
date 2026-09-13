import Foundation

public enum Severity: String, Sendable, Equatable, CaseIterable {
    case normal, warning, critical, unknown
}

public enum StateKey: String, Sendable, Equatable {
    case available, paused, limited, error, unknown
}

public struct PaceSignal: Sendable, Equatable {
    public let value: String
    /// Signed bar fill on a ±50% scale; negative extends left of center.
    public let fill: Double
    public let severity: Severity
    public let numeric: Bool

    static func neutral(_ value: String) -> PaceSignal {
        PaceSignal(value: value, fill: 0, severity: .unknown, numeric: false)
    }
}

public struct WorkloadRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let signal: PaceSignal
    public let stale: Bool
    public let expired: Bool
    public let summary: String
    public let coverageText: String
    public let detail: String
    public let availabilityText: String
    public let freshnessText: String
}

public struct UsageView: Sendable, Equatable {
    public let now: Date
    public let accounts: [AccountBlock]
    public let workloads: [WorkloadRow]
}

public struct ViewOptions: Sendable, Equatable {
    public var showScoped: Bool
    public init(showScoped: Bool = true) { self.showScoped = showScoped }
}

public enum UsageModel {
    public static let staleInterval: TimeInterval = 180

    public static func isStale(_ computedAt: Date?, now: Date, failed: Bool = false) -> Bool {
        failed || computedAt.map { now.timeIntervalSince($0) >= staleInterval } ?? true
    }

    static func countText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "?" }
        return String(clampedInt(value))
    }

    static func ageText(_ date: Date?, now: Date) -> String {
        guard let date else { return "unknown" }
        return "\(Formatting.formatDuration(max(0, now.timeIntervalSince(date)) * 1000)) ago"
    }

    public static func buildView(
        accounts: [Account]?, workloads: WorkloadsResponse?,
        workloadsFailed: Bool = false, accountsFailed: Bool = false,
        options: ViewOptions = ViewOptions(), localNow: Date
    ) -> UsageView {
        let rows = (workloads?.workloads ?? []).filter {
            options.showScoped || !$0.id.orEmpty.hasPrefix("family:")
        }
        var seen = Set<String>()
        let mapped = rows.compactMap { raw -> WorkloadRow? in
            guard let id = nonEmpty(raw.id), seen.insert(id).inserted else { return nil }
            return workloadRow(
                raw, all: workloads?.workloads ?? [], now: localNow, failed: workloadsFailed)
        }
        return UsageView(
            now: localNow,
            accounts: (accounts ?? []).enumerated().map {
                accountBlock(
                    $0.element, index: $0.offset, options: options, now: localNow,
                    failed: accountsFailed)
            },
            workloads: mapped
        )
    }

    public static func paceSignal(_ weekly: WeeklyBudget?) -> PaceSignal {
        if let weekly, weekly.outcome == "exhausted", weekly.quality == "supported",
            let coverage = weekly.coverage, let eligible = coverage.eligibleAccounts, eligible > 0,
            let modeled = coverage.modeledAccounts, modeled > 0
        {
            let complete =
                modeled == eligible && coverage.idleAccounts == 0
                && coverage.learningAccounts == 0 && coverage.unavailableAccounts == 0
            return PaceSignal(
                value: complete ? "Out" : "Subset out", fill: complete ? -100 : 0,
                severity: complete ? .critical : .warning, numeric: false)
        }
        guard let weekly, weekly.quality == "supported",
            ["lasts_until_end", "exhausts_before_end"].contains(weekly.outcome),
            let coverage = weekly.coverage,
            let eligible = coverage.eligibleAccounts, eligible > 0,
            coverage.modeledAccounts == eligible,
            coverage.idleAccounts == 0, coverage.learningAccounts == 0,
            coverage.unavailableAccounts == 0,
            let pace = weekly.pace,
            ["estimate", "conservative_bound"].contains(pace.qualification),
            let value = pace.changePct, value.isFinite, abs(value) <= 100
        else { return .neutral("No reading") }

        let percent = clampedInt(value.rounded())
        guard
            (value >= 0 && weekly.outcome == "lasts_until_end")
                || (value < 0 && weekly.outcome == "exhausts_before_end")
        else {
            return .neutral("No reading")
        }
        let signed = percent > 0 ? "+\(percent)%" : percent < 0 ? "−\(abs(percent))%" : "±0%"
        let bound = pace.qualification == "conservative_bound" ? " bound" : ""
        switch pace.state {
        case "estimate":
            return PaceSignal(
                value: signed + bound, fill: max(-100, min(100, value * 2)),
                severity: value < 0 ? .warning : .normal, numeric: true)
        case "increase_limit" where value > 0:
            return PaceSignal(
                value: "≥\(signed)\(bound)", fill: 100, severity: .normal, numeric: true)
        case "reduction_limit" where value < 0:
            return PaceSignal(
                value: "\(signed) insufficient\(bound)", fill: -100, severity: .warning,
                numeric: true)
        default:
            return .neutral("No reading")
        }
    }

    static func workloadRow(_ raw: Workload, all: [Workload], now: Date, failed: Bool)
        -> WorkloadRow
    {
        let weekly = raw.weekly
        let stale = isStale(weekly?.computedAt.instant, now: now, failed: failed)
        let deadline = weekly?.period?.endsAt.instant
        let expired = deadline.map { $0 <= now } ?? false
        let periodValid = deadline != nil && weekly?.period?.endReason == "next_weekly_reset"
        let lastSignal = paceSignal(weekly)
        let signal: PaceSignal
        if stale {
            signal = .neutral("Stale")
        } else if expired {
            signal = .neutral("Expired")
        } else if !periodValid {
            signal = .neutral("No reading")
        } else {
            signal = lastSignal
        }

        let coverage = weekly?.coverage
        let complete =
            coverage?.eligibleAccounts != nil
            && coverage?.modeledAccounts == coverage?.eligibleAccounts
            && coverage?.idleAccounts == 0 && coverage?.learningAccounts == 0
            && coverage?.unavailableAccounts == 0
        let subset = complete ? "" : " (modeled subset)"
        var summary: String
        switch weekly?.outcome {
        case "exhausted": summary = "Weekly quota exhausted\(subset)"
        case "exhausts_before_end": summary = "Weekly risk\(subset)"
        case "lasts_until_end": summary = "Projected to reach next reset\(subset)"
        case "no_accounts": summary = "No active accounts"
        case "not_applicable": summary = "No weekly subscription quota"
        default: summary = "Forecast unavailable"
        }
        if !["supported", "limited"].contains(weekly?.quality)
            && !["no_accounts", "not_applicable"].contains(weekly?.outcome)
        {
            summary = "Forecast unavailable"
        }
        if weekly?.quality == "limited" { summary += " · limited evidence" }
        if stale {
            summary = "Stale · Last reading: " + summary
        } else if expired {
            summary = "Expired · Last reading: " + summary
        } else if !periodValid && !["no_accounts", "not_applicable"].contains(weekly?.outcome) {
            summary = "No reset checkpoint · " + summary
        }

        var details: [String] = []
        if lastSignal.numeric {
            let prefix: String
            switch weekly?.pace?.state {
            case "increase_limit": prefix = "Tested increase fits"
            case "reduction_limit": prefix = "Tested cut insufficient"
            default: prefix = "Estimated pace"
            }
            details.append(
                "\(stale || expired || !periodValid ? "Last reading · " : "")\(prefix): \(lastSignal.value)"
            )
        } else if let reason = nonEmpty(weekly?.pace?.reason) ?? nonEmpty(weekly?.reason) {
            details.append(Formatting.humanizeStatus(reason))
        }
        if let exhausts = weekly?.exhaustsAt.instant,
            ["exhausted", "exhausts_before_end"].contains(weekly?.outcome)
        {
            details.append("Projected exhaustion\(subset): \(Formatting.formatTimestamp(exhausts))")
        }
        if let deadline {
            details.append(
                "Next reset checkpoint: \(expired ? "expired" : Formatting.formatReset(deadline, now: now))"
            )
        }
        var coverageParts = [
            "\(countText(coverage?.modeledAccounts))/\(countText(coverage?.eligibleAccounts)) modeled"
        ]
        for (count, label) in [
            (coverage?.idleAccounts, "idle"), (coverage?.learningAccounts, "learning"),
            (coverage?.unavailableAccounts, "unreadable"),
        ] {
            if let count, count > 0 { coverageParts.append("\(countText(count)) \(label)") }
        }
        let coverageText = coverageParts.joined(separator: " · ")
        if let risk = weekly?.accountRisk {
            details.append(
                "Accounts: \(countText(risk.spentAccounts)) spent · \(countText(risk.atRiskAccounts)) at risk · \(countText(risk.withinBudgetAccounts)) within budget · \(countText(risk.unknownAccounts)) unassessed"
            )
        }
        if let parent = raw.parentWorkloadId {
            let label = all.first { $0.id == parent }?.label ?? parent
            summary += " · shares \(label)"
            details.append("Overlaps \(label); conservative family bound")
        }

        let availability = raw.availability
        let availabilityStale = isStale(availability?.computedAt.instant, now: now, failed: failed)
        var available =
            "\(countText(availability?.availableAccounts)) available now · \(countText(availability?.constrainedAccounts)) constrained · \(countText(availability?.unknownAccounts)) unknown"
        if availability == nil {
            available = "Availability unavailable"
        } else if availabilityStale {
            available =
                "Stale availability · " + available.replacingOccurrences(of: " now", with: "")
        }
        if let recovery = availability?.nextRecoveryAt.instant {
            available +=
                " · recovery \(recovery <= now ? "due" : Formatting.formatReset(recovery, now: now))"
        }
        let freshness =
            "Weekly computed \(ageText(weekly?.computedAt.instant, now: now)) · evidence \(ageText(weekly?.evidenceObservedAt.instant, now: now))\nAvailability computed \(ageText(availability?.computedAt.instant, now: now))"
        return WorkloadRow(
            id: raw.id ?? "", label: nonEmpty(raw.label) ?? raw.id ?? "Workload",
            signal: signal, stale: stale, expired: expired, summary: summary,
            coverageText: coverageText,
            detail: details.joined(separator: "\n"), availabilityText: available,
            freshnessText: freshness)
    }

    static func accountBlock(
        _ account: Account, index: Int, options: ViewOptions, now: Date, failed: Bool
    ) -> AccountBlock {
        let state = account.availability?.state
        let key: StateKey
        switch state {
        case "available": key = .available
        case "paused": key = .paused
        case "rate_limited", "usage_exhausted": key = .limited
        case "blocked": key = .error
        default: key = .unknown
        }
        var states = [Formatting.humanizeStatus(state)]
        if let observed = account.usageObservedAt.instant {
            states.append("observed \(ageText(observed, now: now))")
        }
        if let reason = nonEmpty(account.availability?.reason) {
            states.append(Formatting.humanizeStatus(reason))
        }
        if let retry = account.availability?.availableAt.instant {
            states.append("retry \(Formatting.formatReset(retry, now: now))")
        }
        if !["valid", "not_applicable"].contains(account.credential?.state) {
            states.append(
                "Credential \(Formatting.humanizeStatus(account.credential?.state).lowercased())")
        }
        if account.measurementState != "fresh" && account.measurementState != "not_applicable" {
            states.append(
                "Usage \(Formatting.humanizeStatus(account.measurementState).lowercased())")
        }
        let windows = (account.windows ?? []).enumerated().compactMap {
            index, window -> WindowRow? in
            let scoped = window.kind == "weekly_scoped" || window.scopeId != nil
            if scoped && !options.showScoped { return nil }
            let percent = Percent.clampPercent(window.utilizationPct)
            let stale = failed || account.measurementState == "stale"
            let expired = window.resetsAt.instant.map { $0 <= now } ?? false
            var severity: Severity =
                stale || expired || percent == nil
                ? .unknown : percent! >= 100 ? .critical : percent! >= 80 ? .warning : .normal
            let forecast = window.forecast
            var forecastText: String
            switch forecast?.outcome {
            case "exhausted": forecastText = "Quota exhausted"
            case "exhausts_before_reset": forecastText = "Risk before reset"
            case "lasts_until_reset": forecastText = "Projected to reach reset"
            default: forecastText = "Forecast unavailable"
            }
            if !["supported", "limited"].contains(forecast?.quality) {
                forecastText = "Forecast unavailable"
            }
            if !stale && !expired && forecast?.quality == "supported"
                && forecast?.outcome == "exhausts_before_reset"
            {
                severity = .warning
            }
            if let reason = nonEmpty(forecast?.reason) {
                forecastText += " · " + Formatting.humanizeStatus(reason)
            }
            if forecast?.quality == "limited" { forecastText += " · limited evidence" }
            if let exhausts = forecast?.exhaustsAt.instant,
                forecast?.outcome == "exhausts_before_reset"
            {
                forecastText += " · \(Formatting.formatTimestamp(exhausts))"
            }
            if let reassess = forecast?.reassessAt.instant {
                forecastText += " · reassess \(Formatting.formatReset(reassess, now: now))"
            }
            if stale {
                forecastText = "Stale · Last reading: " + forecastText
            } else if expired {
                forecastText = "Reset due · Last reading: " + forecastText
            }
            let label =
                nonEmpty(window.label)
                ?? (window.kind == "five_hour"
                    ? "5-hour"
                    : window.kind == "seven_day"
                        ? "Weekly" : Formatting.humanizeStatus(window.scopeId ?? window.kind))
            return WindowRow(
                id: "\(window.kind ?? "window"):\(window.scopeId ?? ""):\(index)",
                label: label, percent: percent, severity: severity,
                forecastText: forecastText,
                resetText: Formatting.formatReset(window.resetsAt.instant, now: now), scoped: scoped
            )
        }
        return AccountBlock(
            id: "\(account.id ?? "account"):\(index)",
            name: nonEmpty(account.name) ?? "Account \(index + 1)",
            provider: Formatting.humanizeStatus(account.provider),
            stateText: states.joined(separator: " · "), stateKey: key,
            windows: windows, emptyText: windows.isEmpty ? "Usage data not available yet" : nil)
    }
}

func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

extension Optional where Wrapped == String {
    fileprivate var orEmpty: String { self ?? "" }
}
